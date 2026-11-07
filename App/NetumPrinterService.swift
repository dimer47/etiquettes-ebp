import CoreBluetooth
import Foundation

/// Imprimante NETUM NT-H861 en Bluetooth LE.
///
/// Même découverte que le SDK iOS NETUM (services `18F0` / `FFF0`, premier
/// caractéristique en écriture, notifications activées pour les réponses),
/// mais l'envoi est découpé à la taille de paquet négociée et régulé par
/// `canSendWriteWithoutResponse` : le SDK écrit jusqu'à 20 000 octets d'un
/// coup, ce que CoreBluetooth ne garantit pas.
@MainActor
final class NetumPrinterService: NSObject, ObservableObject {
    struct Device: Identifiable, Equatable {
        let id: UUID
        let name: String
        let rssi: Int
        let likelyPrinter: Bool
    }

    enum Activity: Equatable { case idle, scanning, connecting, checking, printing }

    @Published private(set) var devices: [Device] = []
    @Published private(set) var activity: Activity = .idle
    @Published private(set) var connected = false
    @Published private(set) var connectedName: String?
    @Published private(set) var status = NSLocalizedString("Aucune NETUM connectée", comment: "NETUM status")
    @Published private(set) var statusIsError = false
    @Published private(set) var lastPrinterStatus: NetumStatus?
    @Published private(set) var progress: Double = 1
    @Published var showAllDevices = false
    /// Échec d'un travail (refusé par l'état ou connexion perdue), pour l'alerte.
    @Published var jobError: String?

    var isBusy: Bool { activity == .printing || activity == .checking }

    private var central: CBCentralManager?
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var peripheral: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?
    private var allDevices: [Device] = []
    private var queue: [UInt8] = []
    /// Position d'envoi dans `queue` : évite de recopier la file à chaque paquet.
    private var queueOffset = 0
    private var userDisconnected = false
    private var inJob = false
    private var queuedTotal = 0
    private var writeType: CBCharacteristicWriteType = .withoutResponse
    private var packetDelay: TimeInterval = 0
    private var waitingForWrite = false
    private var waitingForDelay = false
    private var watchdogArmed = false
    private var statusReader = NetumStatusReader()
    private var statusContinuation: CheckedContinuation<NetumStatus?, Never>?
    private var statusToken = 0
    private var pendingJob: (() -> Void)?
    private var onQueued: (() -> Void)?
    private var automaticReconnect = false
    private var scanTimeout: Task<Void, Never>?
    private var connectTimeout: Task<Void, Never>?

    private static let savedIDKey = "netum.printerID"
    private static let savedNameKey = "netum.printerName"

    override init() {
        super.init()
        connectedName = UserDefaults.standard.string(forKey: Self.savedNameKey)
        central = CBCentralManager(delegate: self, queue: nil)
    }

    // MARK: - Recherche et connexion

    func scan(automaticReconnect: Bool = false) {
        self.automaticReconnect = automaticReconnect
        guard let central, central.state == .poweredOn else {
            // Au lancement l'état vaut encore `.unknown` : `poweredOn` relancera.
            if central?.state == .unknown { return }
            setStatus(NSLocalizedString("Activez Bluetooth pour rechercher la NETUM", comment: "NETUM status"), error: true)
            return
        }
        allDevices.removeAll()
        devices.removeAll()
        peripherals.removeAll()
        // Une NETUM déjà connectée au système n'émet plus d'annonce.
        for known in central.retrieveConnectedPeripherals(withServices: NetumBLE.serviceUUIDs.map { CBUUID(string: $0) }) {
            remember(known, name: known.name ?? "NETUM", rssi: 0, services: NetumBLE.serviceUUIDs)
        }
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        if activity == .idle { activity = .scanning }
        setStatus(NSLocalizedString("Recherche de la NETUM…", comment: "NETUM status"))
        scanTimeout?.cancel()
        scanTimeout = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(15))
            guard let self, !Task.isCancelled else { return }
            self.stopScan()
            // Un travail en attente ne doit pas partir bien plus tard.
            if !self.connected, self.pendingJob != nil {
                self.pendingJob = nil
                self.jobError = NSLocalizedString("NETUM introuvable", comment: "NETUM error")
            }
            if !self.connected { self.setStatus(NSLocalizedString("Aucune NETUM connectée", comment: "NETUM status")) }
        }
    }

    func stopScan() {
        scanTimeout?.cancel()
        central?.stopScan()
        if activity == .scanning { activity = .idle }
    }

    func reconnect() {
        if UserDefaults.standard.string(forKey: Self.savedIDKey) != nil { scan(automaticReconnect: true) }
    }

    func connect(_ device: Device) {
        guard let target = peripherals[device.id] else { return }
        stopScan()
        // Même imprimante déjà connectée ou en cours : rien à refaire.
        if peripheral?.identifier == device.id, connected || activity == .connecting { return }
        if let old = peripheral {
            // Changer d'imprimante : l'ancienne ne doit plus rien recevoir.
            userDisconnected = true
            central?.cancelPeripheralConnection(old)
            reset(NSLocalizedString("Aucune NETUM connectée", comment: "NETUM status"))
        }
        userDisconnected = false
        automaticReconnect = false
        activity = .connecting
        setStatus(String(format: NSLocalizedString("Connexion à %@…", comment: "Printer status"), device.name))
        UserDefaults.standard.set(device.id.uuidString, forKey: Self.savedIDKey)
        UserDefaults.standard.set(device.name, forKey: Self.savedNameKey)
        connectedName = device.name
        peripheral = target
        target.delegate = self
        central?.connect(target)
        // CoreBluetooth n'expire jamais une connexion : on le fait ici.
        connectTimeout?.cancel()
        connectTimeout = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard let self, !Task.isCancelled, !self.connected, self.peripheral?.identifier == device.id else { return }
            self.central?.cancelPeripheralConnection(target)
            self.failPendingJob()
            self.reset(NSLocalizedString("Connexion impossible", comment: "NETUM status"), error: true)
        }
    }

    func disconnect() {
        pendingJob = nil
        userDisconnected = true
        if let peripheral { central?.cancelPeripheralConnection(peripheral) }
        reset(NSLocalizedString("Aucune NETUM connectée", comment: "NETUM status"))
    }

    func applyDeviceFilter() {
        devices = showAllDevices ? allDevices : allDevices.filter(\.likelyPrinter)
    }

    // MARK: - Impression

    /// Construit et envoie le travail. Si l'imprimante n'est pas connectée,
    /// le travail attend la reconnexion automatique.
    func print(bitmap: [UInt8], width: Int, height: Int, options: NetumOptions,
               onQueued: (() -> Void)? = nil) {
        guard !isBusy else {
            jobError = NSLocalizedString("Impression déjà en cours", comment: "NETUM error")
            return
        }
        let bytes: [UInt8]
        do { bytes = try NetumJob.bytes(bitmap: bitmap, width: width, height: height, options: options) }
        catch {
            let text = NSLocalizedString("Étiquette trop large pour ce rouleau", comment: "NETUM error")
            setStatus(text, error: true)
            jobError = text
            return
        }
        let job = { [weak self] in
            guard let self else { return }
            Task { @MainActor in await self.run(bytes, options: options.normalized, onQueued: onQueued) }
        }
        if connected { job() }
        else {
            pendingJob = job
            scan(automaticReconnect: true)
        }
    }

    /// Lit l'état sans imprimer, pour l'écran Imprimante.
    func refreshStatus() {
        guard connected, !isBusy else { return }
        Task { @MainActor in
            activity = .checking
            let result = await readStatus()
            guard connected else { return }
            activity = .idle
            show(result)
        }
    }

    /// Bip seul, pour essayer le réglage.
    func testBeep(count: Int, duration: Int) {
        guard connected, !isBusy else { return }
        enqueue(NetumCommand.beep(count: count, duration: duration))
    }

    private func run(_ bytes: [UInt8], options: NetumOptions, onQueued: (() -> Void)?) async {
        writeType = options.writeWithResponse && writeCharacteristic?.properties.contains(.write) == true
            ? .withResponse : preferredWriteType
        packetDelay = Double(options.packetDelayMS) / 1000
        if options.checkStatusBeforePrint {
            activity = .checking
            let result = await readStatus()
            // Déconnexion pendant la lecture : `reset` a déjà tout remis à zéro.
            guard connected, peripheral != nil else { return }
            // Pas de réponse : certaines versions de firmware ne répondent pas
            // en BLE. On imprime quand même plutôt que de bloquer.
            if let result, !result.canPrint {
                activity = .idle
                show(result)
                jobError = status
                return
            }
            lastPrinterStatus = result
        }
        activity = .printing
        inJob = true
        setStatus(NSLocalizedString("Impression…", comment: "Printer status"))
        self.onQueued = onQueued
        enqueue(bytes)
    }

    private var preferredWriteType: CBCharacteristicWriteType {
        writeCharacteristic?.properties.contains(.writeWithoutResponse) == true ? .withoutResponse : .withResponse
    }

    private func readStatus() async -> NetumStatus? {
        statusReader.reset()
        enqueue(NetumCommand.fullStatusRequest)
        statusToken += 1
        let token = statusToken
        return await withCheckedContinuation { continuation in
            statusContinuation = continuation
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(2))
                // Délai d'une lecture plus ancienne : ne pas clore la suivante.
                guard let self, self.statusToken == token else { return }
                self.finishStatus(nil)
            }
        }
    }

    private func finishStatus(_ status: NetumStatus?) {
        guard let continuation = statusContinuation else { return }
        statusContinuation = nil
        continuation.resume(returning: status)
    }

    private func show(_ result: NetumStatus?) {
        lastPrinterStatus = result
        guard let result else {
            setStatus(NSLocalizedString("Connectée (état non communiqué)", comment: "NETUM status"))
            return
        }
        if result.problems.isEmpty { setStatus(NSLocalizedString("Prête", comment: "NETUM status")) }
        else { setStatus(result.problems.joined(separator: " · "), error: !result.canPrint) }
    }

    // MARK: - File d'écriture

    private func enqueue(_ bytes: [UInt8]) {
        if queueOffset >= queue.count {
            queue.removeAll(keepingCapacity: true)
            queueOffset = 0
            queuedTotal = 0
        }
        queue += bytes
        queuedTotal += bytes.count
        progress = 0
        drain()
    }

    private func drain() {
        guard let peripheral, let characteristic = writeCharacteristic else { return }
        guard !waitingForWrite, !waitingForDelay else { return }
        guard queueOffset < queue.count else {
            queue.removeAll(keepingCapacity: true)
            queueOffset = 0
            progress = 1
            if activity == .printing { finishPrinting() }
            return
        }
        let type = activity == .printing ? writeType : preferredWriteType
        if type == .withoutResponse, !peripheral.canSendWriteWithoutResponse {
            // `peripheralIsReady` n'est pas toujours rappelé : reprise de sécurité.
            armWatchdog()
            return
        }
        // Taille sans accusé (MTU − 3) dans les deux modes : avec accusé,
        // iOS annonce 512 et ferait des écritures longues que ces modules refusent.
        let size = max(20, min(peripheral.maximumWriteValueLength(for: .withoutResponse), 512))
        let end = min(queue.count, queueOffset + size)
        let chunk = Data(queue[queueOffset..<end])
        queueOffset = end
        peripheral.writeValue(chunk, for: characteristic, type: type)
        let remaining = queue.count - queueOffset
        progress = queuedTotal == 0 ? 1 : 1 - Double(remaining) / Double(queuedTotal)
        if type == .withResponse {
            waitingForWrite = true
        } else if packetDelay > 0 {
            waitingForDelay = true
            DispatchQueue.main.asyncAfter(deadline: .now() + packetDelay) { [weak self] in
                self?.waitingForDelay = false
                self?.drain()
            }
        } else {
            DispatchQueue.main.async { [weak self] in self?.drain() }
        }
    }

    private func armWatchdog() {
        guard !watchdogArmed else { return }
        watchdogArmed = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.watchdogArmed = false
            self?.drain()
        }
    }

    private func finishPrinting() {
        activity = .idle
        inJob = false
        // Le protocole ne confirme pas la sortie du papier : seulement l'envoi.
        setStatus(NSLocalizedString("Étiquette envoyée", comment: "NETUM status"))
        let callback = onQueued
        onQueued = nil
        callback?()
    }

    // MARK: - État interne

    private func remember(_ peripheral: CBPeripheral, name: String, rssi: Int, services: [String]) {
        peripherals[peripheral.identifier] = peripheral
        let device = Device(id: peripheral.identifier, name: name, rssi: rssi,
                            likelyPrinter: NetumBLE.looksLikePrinter(name: name, advertisedServices: services))
        allDevices.removeAll { $0.id == device.id }
        allDevices.append(device)
        allDevices.sort { $0.rssi > $1.rssi }
        applyDeviceFilter()
        if automaticReconnect, !connected, activity != .connecting,
           UserDefaults.standard.string(forKey: Self.savedIDKey) == device.id.uuidString {
            connect(device)
        }
    }

    private func reset(_ text: String, error: Bool = false) {
        let wasPrinting = inJob || activity == .printing
        if wasPrinting { jobError = NSLocalizedString("Connexion perdue pendant l’impression", comment: "Printer status") }
        inJob = false
        connected = false
        writeCharacteristic = nil
        peripheral = nil
        queue.removeAll()
        queueOffset = 0
        progress = 1
        waitingForWrite = false
        waitingForDelay = false
        activity = .idle
        finishStatus(nil)
        onQueued = nil
        setStatus(wasPrinting ? NSLocalizedString("Connexion perdue pendant l’impression", comment: "Printer status") : text,
                  error: error || wasPrinting)
    }

    private func setStatus(_ text: String, error: Bool = false) {
        status = text
        statusIsError = error
    }

    private func failPendingJob() {
        guard pendingJob != nil else { return }
        pendingJob = nil
        jobError = NSLocalizedString("NETUM introuvable", comment: "NETUM error")
    }

    private func ready() {
        connectTimeout?.cancel()
        queue.removeAll()
        queueOffset = 0
        connected = true
        activity = .idle
        setStatus(NSLocalizedString("Connectée", comment: "Printer status"))
        if let job = pendingJob {
            pendingJob = nil
            job()
        }
    }
}

extension NetumPrinterService: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            switch central.state {
            case .poweredOn:
                if !connected, activity == .idle,
                   UserDefaults.standard.string(forKey: Self.savedIDKey) != nil || pendingJob != nil {
                    scan(automaticReconnect: true)
                }
            case .unauthorized: reset(NSLocalizedString("Autorisation Bluetooth refusée", comment: "Bluetooth"), error: true)
            case .poweredOff: reset(NSLocalizedString("Bluetooth désactivé", comment: "Bluetooth"), error: true)
            default: reset(NSLocalizedString("Bluetooth indisponible", comment: "Bluetooth"), error: true)
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                                    advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let services = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []).map(\.uuidString)
        let rssi = RSSI.intValue
        Task { @MainActor in
            remember(peripheral, name: name ?? "BLE \(peripheral.identifier.uuidString.prefix(8))",
                     rssi: rssi, services: services)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            guard peripheral === self.peripheral else { return }
            setStatus(NSLocalizedString("Découverte des services…", comment: "NETUM status"))
            peripheral.discoverServices(nil)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            guard peripheral === self.peripheral else { return }
            failPendingJob()
            reset(error?.localizedDescription ?? NSLocalizedString("Connexion impossible", comment: "NETUM status"), error: true)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        let id = peripheral.identifier
        Task { @MainActor in
            // Ancienne imprimante après un changement : ne pas casser la nouvelle.
            guard self.peripheral?.identifier == id else { return }
            reset(NSLocalizedString("Aucune NETUM connectée", comment: "NETUM status"))
            if !userDisconnected { scan(automaticReconnect: true) }
        }
    }
}

extension NetumPrinterService: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        Task { @MainActor in
            guard peripheral === self.peripheral else { return }
            let wanted = NetumBLE.serviceUUIDs.map { CBUUID(string: $0) }
            let services = peripheral.services ?? []
            // Services NETUM d'abord, puis tout service qui accepte l'écriture.
            // Accès générique, attributs et informations : jamais pour l'impression.
            let generic = ["1800", "1801", "180A"].map { CBUUID(string: $0) }
            let usable = services.filter { !generic.contains($0.uuid) }
            let ordered = usable.filter { wanted.contains($0.uuid) } + usable.filter { !wanted.contains($0.uuid) }
            guard !ordered.isEmpty else {
                reset(NSLocalizedString("Aucun service d’impression trouvé", comment: "NETUM status"), error: true)
                return
            }
            for service in ordered { peripheral.discoverCharacteristics(nil, for: service) }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        Task { @MainActor in
            guard peripheral === self.peripheral else { return }
            let wanted = NetumBLE.serviceUUIDs.map { CBUUID(string: $0) }
            for characteristic in service.characteristics ?? [] {
                if characteristic.properties.contains(.notify) || characteristic.properties.contains(.indicate) {
                    peripheral.setNotifyValue(true, for: characteristic)
                }
                let writable = characteristic.properties.contains(.write)
                    || characteristic.properties.contains(.writeWithoutResponse)
                guard writable else { continue }
                // Une caractéristique d'un service NETUM remplace celle d'un
                // service générique trouvée avant, jamais l'inverse.
                let currentIsNetum = writeCharacteristic?.service.map { wanted.contains($0.uuid) } ?? false
                if writeCharacteristic == nil || (wanted.contains(service.uuid) && !currentIsNetum) {
                    writeCharacteristic = characteristic
                }
            }
            if writeCharacteristic != nil, !connected { ready() }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        let bytes = characteristic.value.map { [UInt8]($0) } ?? []
        Task { @MainActor in
            guard statusContinuation != nil, let status = statusReader.consume(bytes) else { return }
            finishStatus(status)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        Task { @MainActor in
            guard peripheral === self.peripheral else { return }
            waitingForWrite = false
            if let error {
                // Fermer le lien : `didDisconnect` relancera la reconnexion.
                central?.cancelPeripheralConnection(peripheral)
                reset(error.localizedDescription, error: true)
                return
            }
            drain()
        }
    }

    nonisolated func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        Task { @MainActor in drain() }
    }
}
