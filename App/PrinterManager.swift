import Combine
import Foundation
import PocketPrinter5890BLE
import PocketPrinter5890Kit

@MainActor
final class PrinterManager: ObservableObject {
    let transport = PocketPrinter5890BLE()
    @Published private(set) var devices: [PrinterDevice] = []
    @Published private(set) var status = NSLocalizedString("Aucune imprimante connectée", comment: "Printer status")
    @Published private(set) var connected = false
    @Published private(set) var connectedDeviceName: String?
    @Published private(set) var batteryPercent: Int?
    @Published var printerAlias = "" {
        didSet {
            guard let id = UserDefaults.standard.string(forKey: "printerID") else { return }
            UserDefaults.standard.set(printerAlias, forKey: "printerAlias.\(id)")
        }
    }
    var displayName: String {
        let alias = printerAlias.trimmingCharacters(in: .whitespacesAndNewlines)
        return alias.isEmpty ? (connectedDeviceName ?? "Pocket Printer 5890") : alias
    }
    @Published private(set) var printing = false
    @Published var density: PrintDensity = .medium {
        didSet { UserDefaults.standard.set(Int(density.rawValue), forKey: "density") }
    }
    /// 104 dots is roughly 13 mm: halfway between the original 10 mm and
    /// the 16 mm trial that advanced too much paper.
    @Published var trailingFeedDots = 104 {
        didSet { UserDefaults.standard.set(trailingFeedDots, forKey: "trailingFeedDots") }
    }
    @Published var leadingFeedDots = 0 {
        didSet { UserDefaults.standard.set(leadingFeedDots, forKey: "leadingFeedDots") }
    }
    @Published var rotateContent180 = false {
        didSet { UserDefaults.standard.set(rotateContent180, forKey: "rotateContent180") }
    }
    private var cancellables = Set<AnyCancellable>()
    private var pendingBitmap: MonochromeBitmap?
    private var pendingOnQueued: (() -> Void)?
    private var automaticReconnect = false
    private var scanTimeout: Task<Void, Never>?

    init() {
        if UserDefaults.standard.object(forKey: "density") != nil,
           let saved = PrintDensity(rawValue: UInt8(clamping: UserDefaults.standard.integer(forKey: "density"))) { density = saved }
        if let saved = UserDefaults.standard.object(forKey: "trailingFeedDots") as? Int {
            trailingFeedDots = saved
        }
        if let saved = UserDefaults.standard.object(forKey: "leadingFeedDots") as? Int {
            leadingFeedDots = max(0, min(saved, 80))
        }
        rotateContent180 = UserDefaults.standard.bool(forKey: "rotateContent180")
        if let id = UserDefaults.standard.string(forKey: "printerID") {
            printerAlias = UserDefaults.standard.string(forKey: "printerAlias.\(id)") ?? ""
            connectedDeviceName = UserDefaults.standard.string(forKey: "printerName.\(id)")
        }
        transport.$batteryPercent.sink { [weak self] value in
            self?.batteryPercent = value
        }.store(in: &cancellables)
        transport.$devices.sink { [weak self] found in
            guard let self else { return }
            self.devices = found
            guard self.automaticReconnect, !self.connected, let id = UserDefaults.standard.string(forKey: "printerID"),
                  let known = found.first(where: { $0.id.uuidString == id }) else { return }
            self.connect(known)
        }.store(in: &cancellables)
        transport.$isConnected.sink { [weak self] connected in
            guard let self else { return }
            self.connected = connected
            self.status = connected ? NSLocalizedString("Connectée", comment: "Printer status") : NSLocalizedString("Aucune imprimante connectée", comment: "Printer status")
            if !connected { self.batteryPercent = nil }
            if connected, let bitmap = self.pendingBitmap {
                self.pendingBitmap = nil
                let onQueued = self.pendingOnQueued
                self.pendingOnQueued = nil
                self.send(bitmap, onQueued: onQueued)
            }
        }.store(in: &cancellables)
    }

    func scan(automaticReconnect: Bool = false) {
        self.automaticReconnect = automaticReconnect
        Task { @MainActor in
            for _ in 0..<20 {
                transport.startScan()
                if transport.isScanning { break }
                try? await Task.sleep(for: .milliseconds(150))
            }
            if transport.isScanning {
                status = NSLocalizedString("Recherche de la 5890…", comment: "Printer status")
                scanTimeout?.cancel()
                scanTimeout = Task { @MainActor in
                    try? await Task.sleep(for: .seconds(15))
                    guard !Task.isCancelled else { return }
                    transport.stopScan()
                    if !connected { status = NSLocalizedString("Aucune imprimante connectée", comment: "Printer status") }
                }
            } else { status = NSLocalizedString("Activez Bluetooth pour rechercher la 5890", comment: "Printer status") }
        }
    }

    func reconnect() {
        if UserDefaults.standard.string(forKey: "printerID") != nil { scan(automaticReconnect: true) }
    }

    func connect(_ device: PrinterDevice) {
        scanTimeout?.cancel()
        automaticReconnect = false
        transport.stopScan()
        status = String(format: NSLocalizedString("Connexion à %@…", comment: "Printer status"), device.name)
        UserDefaults.standard.set(device.id.uuidString, forKey: "printerID")
        UserDefaults.standard.set(device.name, forKey: "printerName.\(device.id.uuidString)")
        connectedDeviceName = device.name
        printerAlias = UserDefaults.standard.string(forKey: "printerAlias.\(device.id.uuidString)") ?? ""
        transport.connect(to: device)
    }

    func disconnect() {
        pendingBitmap = nil
        pendingOnQueued = nil
        transport.disconnect()
        status = NSLocalizedString("Aucune imprimante connectée", comment: "Printer status")
    }

    func print(_ bitmap: MonochromeBitmap, onQueued: (() -> Void)? = nil) {
        guard !printing else { return }
        guard let prepared = try? preparedBitmap(bitmap) else {
            status = NSLocalizedString("Impossible de tourner le bitmap", comment: "Print error")
            return
        }
        if connected { send(prepared, onQueued: onQueued) }
        else {
            pendingBitmap = prepared
            pendingOnQueued = onQueued
            scan(automaticReconnect: true)
        }
    }

    func preparedBitmap(_ bitmap: MonochromeBitmap) throws -> MonochromeBitmap {
        if rotateContent180 { return try bitmap.rotated180() }
        return bitmap
    }

    private func send(_ bitmap: MonochromeBitmap, onQueued: (() -> Void)? = nil) {
        printing = true
        status = NSLocalizedString("Impression…", comment: "Printer status")
        let options = PrintOptions(width: .mm58, density: density, trailingFeedDots: trailingFeedDots, paperMode: .continuous)
        var elements: [PrintElement] = []
        if leadingFeedDots > 0 {
            // The document is sent after PrintJobBuilder's activation sequence;
            // a bare feed before activation is ignored by the 5890 firmware.
            elements.append(.raw(ESCPOS.feed(dots: leadingFeedDots)))
        }
        elements.append(.image(bitmap))
        transport.send(PrintJobBuilder.segments(document: PrintDocument(elements: elements), options: options))
        onQueued?()
        Task { @MainActor in
            // The transport exposes queue progress but no physical completion acknowledgement.
            while transport.sendProgress < 1 && transport.isConnected {
                try? await Task.sleep(for: .milliseconds(200))
            }
            printing = false
            status = transport.isConnected ? NSLocalizedString("Connectée", comment: "Printer status") : NSLocalizedString("Connexion perdue pendant l’impression", comment: "Printer status")
        }
    }
}
