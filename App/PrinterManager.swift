import Combine
import Foundation
import PocketPrinter5890BLE
import PocketPrinter5890Kit

@MainActor
final class PrinterManager: ObservableObject {
    let transport = PocketPrinter5890BLE()
    @Published private(set) var devices: [PrinterDevice] = []
    @Published private(set) var status = "Aucune imprimante connectée"
    @Published private(set) var connected = false
    @Published private(set) var printing = false
    @Published var density: PrintDensity = .medium {
        didSet { UserDefaults.standard.set(Int(density.rawValue), forKey: "density") }
    }
    /// 104 dots is roughly 13 mm: halfway between the original 10 mm and
    /// the 16 mm trial that advanced too much paper.
    @Published var trailingFeedDots = 104 {
        didSet { UserDefaults.standard.set(trailingFeedDots, forKey: "trailingFeedDots") }
    }
    private var cancellables = Set<AnyCancellable>()
    private var pendingBitmap: MonochromeBitmap?
    private var automaticReconnect = false
    private var scanTimeout: Task<Void, Never>?

    init() {
        if UserDefaults.standard.object(forKey: "density") != nil,
           let saved = PrintDensity(rawValue: UInt8(clamping: UserDefaults.standard.integer(forKey: "density"))) { density = saved }
        if let saved = UserDefaults.standard.object(forKey: "trailingFeedDots") as? Int {
            // The user asked to halve the extra advance from the 16 mm trial.
            // Migrate that value even if it was explicitly selected in build 4.
            trailingFeedDots = saved == 128 ? 104 : saved
            if saved == 128 { UserDefaults.standard.set(104, forKey: "trailingFeedDots") }
        }
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
            self.status = connected ? "5890 connectée" : "Aucune imprimante connectée"
            if connected, let bitmap = self.pendingBitmap {
                self.pendingBitmap = nil
                self.send(bitmap)
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
                status = "Recherche de la 5890…"
                scanTimeout?.cancel()
                scanTimeout = Task { @MainActor in
                    try? await Task.sleep(for: .seconds(15))
                    guard !Task.isCancelled else { return }
                    transport.stopScan()
                    if !connected { status = "Aucune imprimante connectée" }
                }
            } else { status = "Activez Bluetooth pour rechercher la 5890" }
        }
    }

    func reconnect() {
        if UserDefaults.standard.string(forKey: "printerID") != nil { scan(automaticReconnect: true) }
    }

    func connect(_ device: PrinterDevice) {
        scanTimeout?.cancel()
        automaticReconnect = false
        transport.stopScan()
        status = "Connexion à \(device.name)…"
        UserDefaults.standard.set(device.id.uuidString, forKey: "printerID")
        transport.connect(to: device)
    }

    func disconnect() {
        pendingBitmap = nil
        transport.disconnect()
        status = "Aucune imprimante connectée"
    }

    func print(_ bitmap: MonochromeBitmap) {
        guard !printing else { return }
        if connected { send(bitmap) }
        else { pendingBitmap = bitmap; scan(automaticReconnect: true) }
    }

    private func send(_ bitmap: MonochromeBitmap) {
        printing = true
        status = "Impression…"
        let options = PrintOptions(width: .mm58, density: density, trailingFeedDots: trailingFeedDots, paperMode: .continuous)
        transport.send(PrintJobBuilder.segments(bitmap: bitmap, options: options))
        Task { @MainActor in
            // The transport exposes queue progress but no physical completion acknowledgement.
            while transport.sendProgress < 1 && transport.isConnected {
                try? await Task.sleep(for: .milliseconds(200))
            }
            printing = false
            status = transport.isConnected ? "5890 connectée" : "Connexion perdue pendant l’impression"
        }
    }
}
