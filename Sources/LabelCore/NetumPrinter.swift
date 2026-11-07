import Foundation

// Imprimante ticket NETUM NT-H861 (et NT-306 / NT-806, même SDK) :
// tête thermique 80 mm de 576 points à 203 dpi, massicot, ESC/POS.
//
// Ce fichier ne dépend ni de CoreBluetooth ni d'UIKit : il décrit le papier,
// les réglages et construit les octets ESC/POS d'un travail. Les commandes
// reprennent celles du SDK iOS officiel NETUM (`PosCommand.h`), réécrites en
// Swift pour ne pas embarquer le code Objective-C du fabricant.

/// Rouleau chargé dans l'imprimante. Le séparateur de papier fourni permet
/// un rouleau de 58 mm (57 mm pour les rouleaux de terminal de paiement).
public enum NetumPaper: String, CaseIterable, Identifiable, Codable, Sendable {
    case mm80
    case mm58

    public var id: String { rawValue }

    /// Largeur de la tête, quel que soit le rouleau.
    public static let headDots = 576
    public static let dotsPerMM = 8.0

    /// Points imprimables sur ce rouleau.
    public var printableDots: Int {
        switch self {
        case .mm80: 576
        case .mm58: 384
        }
    }

    /// Largeur de la mise en page : 576 points pour les dispositions 80 mm,
    /// 384 pour reprendre exactement celles de la 5890 sur 58 mm.
    public var layoutWidth: Int { printableDots }

    public var printableMM: Int { Int(Double(printableDots) / Self.dotsPerMM) }

    public var title: String {
        switch self {
        case .mm80: NSLocalizedString("Rouleau 80 mm", comment: "NETUM paper")
        case .mm58: NSLocalizedString("Rouleau 58 / 57 mm", comment: "NETUM paper")
        }
    }
}

/// Coupe en fin d'étiquette (`GS V`).
public enum NetumCut: String, CaseIterable, Identifiable, Codable, Sendable {
    /// L'étiquette tombe.
    case full
    /// Un point d'attache retient l'étiquette.
    case partial
    /// Pas de coupe : le papier avance pour être déchiré.
    case none

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .full: NSLocalizedString("Coupe totale", comment: "NETUM cut")
        case .partial: NSLocalizedString("Coupe partielle", comment: "NETUM cut")
        case .none: NSLocalizedString("Pas de coupe", comment: "NETUM cut")
        }
    }
}

/// Réglages d'impression de la NETUM, conservés dans `UserDefaults`.
public struct NetumOptions: Codable, Equatable, Sendable {
    public var paper: NetumPaper = .mm80
    public var cut: NetumCut = .full
    /// Papier avancé avant la première ligne imprimée.
    public var leadingFeedDots = 0
    /// Papier ajouté après l'étiquette. Avec coupe, `GS V` amène déjà la fin
    /// de l'impression sous la lame : cette valeur n'est qu'une marge blanche.
    public var trailingFeedDots = 16
    /// Décalage de l'image vers la droite, pour centrer un rouleau 58 mm
    /// selon la position du séparateur.
    public var leftMarginDots = 0
    public var rotateContent180 = false
    /// Bip en fin d'étiquette (`ESC B n t`).
    public var beep = false
    /// Nombre de bips, 1 à 9.
    public var beepCount = 1
    /// Durée de chaque bip en pas de 50 ms, 1 à 9.
    public var beepDuration = 2
    /// Lit l'état (papier, capot, massicot) avant d'imprimer.
    public var checkStatusBeforePrint = true
    public var copies = 1
    /// Écriture BLE avec accusé : plus lent, utile si des lignes se perdent.
    public var writeWithResponse = false
    /// Pause entre paquets BLE, en millisecondes.
    public var packetDelayMS = 0

    public init() {}

    public static let leftMarginRange = 0...192
    public static let feedRange = 0...255
    public static let beepRange = 1...9
    public static let copiesRange = 1...99
    public static let packetDelayRange = 0...50

    /// Valeurs ramenées dans les bornes acceptées par l'imprimante.
    public var normalized: NetumOptions {
        var copy = self
        copy.leadingFeedDots = Self.clamp(leadingFeedDots, Self.feedRange)
        copy.trailingFeedDots = Self.clamp(trailingFeedDots, Self.feedRange)
        let freeDots = NetumPaper.headDots - paper.printableDots
        copy.leftMarginDots = Self.clamp(leftMarginDots, 0...min(Self.leftMarginRange.upperBound, freeDots))
        copy.beepCount = Self.clamp(beepCount, Self.beepRange)
        copy.beepDuration = Self.clamp(beepDuration, Self.beepRange)
        copy.copies = Self.clamp(copies, Self.copiesRange)
        copy.packetDelayMS = Self.clamp(packetDelayMS, Self.packetDelayRange)
        return copy
    }

    private static func clamp(_ value: Int, _ range: ClosedRange<Int>) -> Int {
        min(range.upperBound, max(range.lowerBound, value))
    }

    // Décodage tolérant : un réglage ajouté plus tard garde sa valeur par
    // défaut au lieu de faire perdre tous les autres.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = NetumOptions()
        paper = (try? c.decode(NetumPaper.self, forKey: .paper)) ?? d.paper
        cut = (try? c.decode(NetumCut.self, forKey: .cut)) ?? d.cut
        leadingFeedDots = (try? c.decode(Int.self, forKey: .leadingFeedDots)) ?? d.leadingFeedDots
        trailingFeedDots = (try? c.decode(Int.self, forKey: .trailingFeedDots)) ?? d.trailingFeedDots
        leftMarginDots = (try? c.decode(Int.self, forKey: .leftMarginDots)) ?? d.leftMarginDots
        rotateContent180 = (try? c.decode(Bool.self, forKey: .rotateContent180)) ?? d.rotateContent180
        beep = (try? c.decode(Bool.self, forKey: .beep)) ?? d.beep
        beepCount = (try? c.decode(Int.self, forKey: .beepCount)) ?? d.beepCount
        beepDuration = (try? c.decode(Int.self, forKey: .beepDuration)) ?? d.beepDuration
        checkStatusBeforePrint = (try? c.decode(Bool.self, forKey: .checkStatusBeforePrint)) ?? d.checkStatusBeforePrint
        copies = (try? c.decode(Int.self, forKey: .copies)) ?? d.copies
        writeWithResponse = (try? c.decode(Bool.self, forKey: .writeWithResponse)) ?? d.writeWithResponse
        packetDelayMS = (try? c.decode(Int.self, forKey: .packetDelayMS)) ?? d.packetDelayMS
    }
}

// MARK: - Commandes ESC/POS

/// Commandes du SDK NETUM utilisées par l'app.
public enum NetumCommand {
    /// `ESC @` : remet l'imprimante dans son état par défaut.
    public static let initialize: [UInt8] = [0x1B, 0x40]

    /// `ESC J n` : avance de `dots` points, découpée en pas de 255.
    public static func feed(dots: Int) -> [UInt8] {
        var remaining = max(0, dots)
        var bytes: [UInt8] = []
        while remaining > 0 {
            let step = min(255, remaining)
            bytes += [0x1B, 0x4A, UInt8(step)]
            remaining -= step
        }
        return bytes
    }

    /// `GS V 65 n` (totale) ou `GS V 66 n` (partielle) : amène la fin de
    /// l'impression sous la lame, avance encore de `n` points, puis coupe.
    /// Sans coupe, simple avance.
    public static func cut(_ cut: NetumCut, extraFeedDots: Int) -> [UInt8] {
        let n = UInt8(min(255, max(0, extraFeedDots)))
        switch cut {
        case .full: return [0x1D, 0x56, 0x41, n]
        case .partial: return [0x1D, 0x56, 0x42, n]
        case .none: return feed(dots: extraFeedDots)
        }
    }

    /// `ESC B n t` : `count` bips de `duration` × 50 ms (1 à 9 chacun).
    public static func beep(count: Int, duration: Int) -> [UInt8] {
        [0x1B, 0x42, UInt8(min(9, max(1, count))), UInt8(min(9, max(1, duration)))]
    }

    /// `DLE EOT n` : état en temps réel, `n` de 1 à 4. L'imprimante répond
    /// un octet par demande, même en cours d'impression.
    public static func realTimeStatus(_ n: UInt8) -> [UInt8] {
        [0x10, 0x04, min(4, max(1, n))]
    }

    /// Les quatre demandes d'état, dans l'ordre attendu par `NetumStatus`.
    public static let fullStatusRequest: [UInt8] = (1...4).flatMap { realTimeStatus(UInt8($0)) }

    /// Hauteur d'une bande raster : celle du SDK NETUM.
    public static let rasterBandRows = 24

    /// `GS v 0` en bandes de 24 lignes. `bytes` : 1 bit par point, bit 7 à
    /// gauche, lignes alignées sur l'octet.
    public static func raster(_ bytes: [UInt8], width: Int, height: Int) throws -> [UInt8] {
        let widthBytes = (width + 7) / 8
        guard width > 0, height > 0, widthBytes <= 0xFFFF, bytes.count == widthBytes * height else {
            throw NetumError.invalidBitmap
        }
        var out: [UInt8] = []
        out.reserveCapacity(bytes.count + (height / rasterBandRows + 1) * 8)
        var row = 0
        while row < height {
            let rows = min(rasterBandRows, height - row)
            out += [0x1D, 0x76, 0x30, 0x00,
                    UInt8(widthBytes & 0xFF), UInt8(widthBytes >> 8),
                    UInt8(rows & 0xFF), UInt8(rows >> 8)]
            out += bytes[(row * widthBytes)..<((row + rows) * widthBytes)]
            row += rows
        }
        return out
    }
}

public enum NetumError: Error, Equatable {
    case invalidBitmap
    case bitmapTooWide
}

// MARK: - Travail d'impression

public enum NetumJob {
    /// Place l'étiquette sur la largeur de la tête : `leftMarginDots` blancs
    /// à gauche, puis l'image, complétée à droite jusqu'à un multiple de 8.
    public static func placed(_ bytes: [UInt8], width: Int, height: Int,
                              leftMarginDots: Int) throws -> (bytes: [UInt8], width: Int) {
        let widthBytes = (width + 7) / 8
        guard width > 0, height > 0, bytes.count == widthBytes * height else { throw NetumError.invalidBitmap }
        let left = max(0, leftMarginDots)
        guard left + width <= NetumPaper.headDots else { throw NetumError.bitmapTooWide }
        if left == 0 { return (bytes, width) }
        let outWidth = (left + width + 7) / 8 * 8
        let outBytes = outWidth / 8
        var out = [UInt8](repeating: 0, count: outBytes * height)
        for y in 0..<height {
            for x in 0..<width where bytes[y * widthBytes + x / 8] & UInt8(0x80 >> (x % 8)) != 0 {
                let target = left + x
                out[y * outBytes + target / 8] |= UInt8(0x80 >> (target % 8))
            }
        }
        return (out, outWidth)
    }

    /// Octets d'un travail complet : une étiquette par copie, chacune suivie
    /// de sa coupe, puis le bip une seule fois à la fin.
    public static func bytes(bitmap: [UInt8], width: Int, height: Int,
                             options: NetumOptions) throws -> [UInt8] {
        let options = options.normalized
        guard width <= options.paper.printableDots else { throw NetumError.bitmapTooWide }
        let placed = try placed(bitmap, width: width, height: height, leftMarginDots: options.leftMarginDots)
        let label = try NetumCommand.raster(placed.bytes, width: placed.width, height: height)
        var out = NetumCommand.initialize
        for _ in 0..<options.copies {
            out += NetumCommand.feed(dots: options.leadingFeedDots)
            out += label
            out += NetumCommand.cut(options.cut, extraFeedDots: options.trailingFeedDots)
        }
        if options.beep {
            out += NetumCommand.beep(count: options.beepCount, duration: options.beepDuration)
        }
        return out
    }
}

// MARK: - État

/// Réponse aux quatre `DLE EOT n`.
public struct NetumStatus: Equatable, Sendable {
    public var offline = false
    public var coverOpen = false
    public var feedButtonPressed = false
    public var paperEnd = false
    public var paperNearEnd = false
    public var cutterError = false
    public var unrecoverableError = false
    public var recoverableError = false

    public init() {}

    /// `responses` : un octet par demande, n = 1 à 4 dans l'ordre. Chaque
    /// octet d'état ESC/POS a les bits 1 et 4 à 1, les bits 0 et 7 à 0 :
    /// tout autre octet est refusé.
    public init?(responses: [UInt8]) {
        guard responses.count == 4, responses.allSatisfy(Self.isStatusByte) else { return nil }
        let printer = responses[0], offlineCause = responses[1], error = responses[2], paper = responses[3]
        offline = printer & 0x08 != 0
        coverOpen = offlineCause & 0x04 != 0
        feedButtonPressed = offlineCause & 0x08 != 0
        paperEnd = offlineCause & 0x20 != 0 || paper & 0x60 != 0
        paperNearEnd = paper & 0x0C != 0
        cutterError = error & 0x08 != 0
        unrecoverableError = error & 0x20 != 0
        recoverableError = error & 0x40 != 0
    }

    public static func isStatusByte(_ byte: UInt8) -> Bool { byte & 0x93 == 0x12 }

    /// Rien n'empêche d'imprimer. Papier presque fini : on imprime quand même.
    public var canPrint: Bool {
        !coverOpen && !paperEnd && !cutterError && !unrecoverableError && !recoverableError
    }

    /// Problèmes à afficher, du plus bloquant au moins bloquant.
    public var problems: [String] {
        var list: [String] = []
        if coverOpen { list.append(NSLocalizedString("Capot ouvert", comment: "NETUM status")) }
        if paperEnd { list.append(NSLocalizedString("Plus de papier", comment: "NETUM status")) }
        if cutterError { list.append(NSLocalizedString("Erreur du massicot", comment: "NETUM status")) }
        if unrecoverableError { list.append(NSLocalizedString("Erreur imprimante", comment: "NETUM status")) }
        if recoverableError { list.append(NSLocalizedString("Erreur passagère, réessayez", comment: "NETUM status")) }
        if paperNearEnd { list.append(NSLocalizedString("Papier presque terminé", comment: "NETUM status")) }
        return list
    }
}

/// Accumule les octets reçus jusqu'à avoir les quatre réponses d'état.
/// Les octets qui ne sont pas des octets d'état sont ignorés.
public struct NetumStatusReader: Sendable {
    private var bytes: [UInt8] = []
    public init() {}

    public mutating func reset() { bytes.removeAll() }

    /// Renvoie l'état une fois les quatre octets reçus.
    public mutating func consume(_ incoming: [UInt8]) -> NetumStatus? {
        bytes += incoming.filter(NetumStatus.isStatusByte)
        guard bytes.count >= 4 else { return nil }
        let status = NetumStatus(responses: Array(bytes.prefix(4)))
        bytes.removeAll()
        return status
    }
}

// MARK: - Services BLE

/// Services BLE recherchés par le SDK NETUM : `18F0` pour les imprimantes
/// de bureau, `FFF0` pour les portables.
public enum NetumBLE {
    public static let serviceUUIDs = ["18F0", "FFF0"]

    /// Nom annoncé qui ressemble à une imprimante NETUM ou ticket générique.
    public static func looksLikePrinter(name: String, advertisedServices: [String]) -> Bool {
        if advertisedServices.contains(where: { uuid in serviceUUIDs.contains { $0.caseInsensitiveCompare(uuid) == .orderedSame } }) {
            return true
        }
        let lower = name.lowercased()
        return ["netum", "printer", "pos", "nt-", "h861", "806", "306", "rpp", "xp-"].contains { lower.contains($0) }
    }
}
