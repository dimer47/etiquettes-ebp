import Foundation

// Catalogue des imprimantes que l'application sait piloter.
//
// Le choix de l'imprimante vient avant celui du papier : la Pocket 5890
// n'accepte qu'un rouleau ticket de 58 mm, une Brother TD-4550DNWB des
// rouleaux et des étiquettes jusqu'à 4 pouces, une QL des rouleaux DK à
// référence fixe. Les listes de papier dépendent donc toujours du modèle.
//
// Ce fichier n'a aucune dépendance au SDK Brother : il décrit les modèles et
// leurs capacités. Le pilotage réel (BRLMPrinterKit) vit dans l'application,
// parce que le SDK est un binaire propriétaire que ce dépôt ne redistribue pas.

/// Famille d'imprimante, choisie en premier.
public enum PrinterBrand: String, CaseIterable, Identifiable, Codable, Sendable {
    /// Imprimante de poche SilverCrest / Tronic, modèle 5890.
    case pocket5890
    /// Imprimantes Brother pilotées par le Brother Print SDK.
    case brother

    public var id: String { rawValue }
}

// MARK: - Séries et capacités

/// Série Brother. Elle détermine la classe de réglages du SDK et le papier.
public enum BrotherSeries: String, CaseIterable, Identifiable, Codable, Sendable {
    /// Étiquettes et tickets, papier personnalisé (`BRLMTDPrintSettings`).
    case td
    /// Mobiles ticket et étiquettes, papier personnalisé (`BRLMRJPrintSettings`).
    case rj
    /// Étiquettes DK à références fixes (`BRLMQLPrintSettings`).
    case ql
    /// Rubans P-touch TZe/HSe (`BRLMPTPrintSettings`).
    case pt
    /// Mobiles A4/Letter (`BRLMPJPrintSettings`).
    case pj
    /// Mobiles A6/A7 (`BRLMMWPrintSettings`).
    case mw

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .td: return "TD"
        case .rj: return "RJ"
        case .ql: return "QL"
        case .pt: return "PT (P-touch)"
        case .pj: return "PJ"
        case .mw: return "MW"
        }
    }

    public var paperSource: BrotherPaperSource {
        switch self {
        case .td, .rj: return .customPaper
        case .ql: return .qlLabel
        case .pt: return .ptTape
        case .pj: return .pjSheet
        case .mw: return .fixedByModel
        }
    }

    /// Coupe pilotable par le SDK pour cette série.
    ///
    /// TD : `autoCut`, `autoCutForEachPageCount`, `cutAtEnd`, mais le
    /// massicot est un accessoire matériel. QL : les trois, massicot intégré.
    /// PT : `autoCut` et `autoCutForEachPageCount`, pas de `cutAtEnd`.
    /// RJ, PJ, MW : aucune.
    public var cutter: BrotherCutterSupport {
        switch self {
        case .td: return .optionalUnit
        case .ql: return .builtIn
        case .pt: return .autoCutOnly
        case .rj, .pj, .mw: return .none
        }
    }
}

public enum BrotherCutterSupport: String, Codable, Sendable {
    /// Pas de coupe pilotable.
    case none
    /// Massicot intégré (QL).
    case builtIn
    /// Massicot vendu en option (TD) : à installer sur l'imprimante.
    case optionalUnit
    /// Coupe automatique sans coupe en fin (PT) ; certaines P-touch n'ont
    /// qu'une coupe manuelle.
    case autoCutOnly

    public var isControllable: Bool { self != .none }
    /// `autoCutForEachPageCount` : TD, QL et PT (BRLMPTPrintSettings.h).
    public var supportsCutEvery: Bool { self != .none }
    /// `cutAtEnd` : TD et QL seulement.
    public var supportsCutAtEnd: Bool { self == .optionalUnit || self == .builtIn }
}

/// Interface de communication.
public enum BrotherConnection: String, CaseIterable, Identifiable, Codable, Sendable {
    /// Bluetooth Low Energy : recherche par nom local annoncé.
    case ble
    /// Wi-Fi : recherche sur le réseau local, ou adresse IP.
    case wifi
    /// Bluetooth Classic MFi : non géré par l'application (framework
    /// `BT_Net`, Product Plan ID Brother, accessoire externe).
    case bluetoothClassic

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .ble: return "Bluetooth LE"
        case .wifi: return "Wi-Fi"
        case .bluetoothClassic: return "Bluetooth Classic (MFi)"
        }
    }
}

// MARK: - Modèles

/// Modèles de l'énumération `BRLMPrinterModel` (BRLMPrinterDefine.h, SDK 4.13.2).
///
/// Le nom des cas reprend celui du SDK ; la valeur brute est la référence
/// commerciale. RJ-2031, RJ-2131 et PT-P750Wc n'existent qu'à partir du
/// SDK 4.13.2 (absents des 4.13.0 et 4.13.1).
public enum BrotherModel: String, CaseIterable, Identifiable, Codable, Sendable {
    // swiftlint:disable identifier_name
    case PJ_673 = "PJ-673"
    case PJ_763MFi = "PJ-763MFi"
    case PJ_773 = "PJ-773"
    case PJ_822 = "PJ-822"
    case PJ_823 = "PJ-823"
    case PJ_862 = "PJ-862"
    case PJ_863 = "PJ-863"
    case PJ_883 = "PJ-883"
    case MW_145MFi = "MW-145MFi"
    case MW_260MFi = "MW-260MFi"
    case MW_170 = "MW-170"
    case MW_270 = "MW-270"
    case RJ_2031 = "RJ-2031"
    case RJ_2050 = "RJ-2050"
    case RJ_2131 = "RJ-2131"
    case RJ_2140 = "RJ-2140"
    case RJ_2150 = "RJ-2150"
    case RJ_3050 = "RJ-3050"
    case RJ_3050Ai = "RJ-3050Ai"
    case RJ_3150 = "RJ-3150"
    case RJ_3150Ai = "RJ-3150Ai"
    case RJ_3230B = "RJ-3230B"
    case RJ_3235B = "RJ-3235B"
    case RJ_3250WB = "RJ-3250WB"
    case RJ_3255WB = "RJ-3255WB"
    case RJ_4030Ai = "RJ-4030Ai"
    case RJ_4040 = "RJ-4040"
    case RJ_4230B = "RJ-4230B"
    case RJ_4235B = "RJ-4235B"
    case RJ_4250WB = "RJ-4250WB"
    case RJ_4255WB = "RJ-4255WB"
    case TD_2030A = "TD-2030A"
    case TD_2120N = "TD-2120N"
    case TD_2125N = "TD-2125N"
    case TD_2125NWB = "TD-2125NWB"
    case TD_2130N = "TD-2130N"
    case TD_2135N = "TD-2135N"
    case TD_2135NWB = "TD-2135NWB"
    case TD_2310D_203 = "TD-2310D_203"
    case TD_2310D_300 = "TD-2310D_300"
    case TD_2320D_203 = "TD-2320D_203"
    case TD_2320D_300 = "TD-2320D_300"
    case TD_2320DF_203 = "TD-2320DF_203"
    case TD_2320DF_300 = "TD-2320DF_300"
    case TD_2320DSA_203 = "TD-2320DSA_203"
    case TD_2320DSA_300 = "TD-2320DSA_300"
    case TD_2350D_203 = "TD-2350D_203"
    case TD_2350D_300 = "TD-2350D_300"
    case TD_2350DF_203 = "TD-2350DF_203"
    case TD_2350DF_300 = "TD-2350DF_300"
    case TD_2350DSA_203 = "TD-2350DSA_203"
    case TD_2350DSA_300 = "TD-2350DSA_300"
    case TD_2350DFSA_203 = "TD-2350DFSA_203"
    case TD_2350DFSA_300 = "TD-2350DFSA_300"
    case TD_4100N = "TD-4100N"
    case TD_4415D = "TD-4415D"
    case TD_4420DN = "TD-4420DN"
    case TD_4425DN = "TD-4425DN"
    case TD_4425DNF = "TD-4425DNF"
    case TD_4455DNWB = "TD-4455DNWB"
    case TD_4520DN = "TD-4520DN"
    case TD_4525DN = "TD-4525DN"
    case TD_4550DNWB = "TD-4550DNWB"
    case TD_4555DNWB = "TD-4555DNWB"
    case TD_4555DNWBF = "TD-4555DNWBF"
    case QL_710W = "QL-710W"
    case QL_720NW = "QL-720NW"
    case QL_810W = "QL-810W"
    case QL_820NWB = "QL-820NWB"
    case QL_1110NWB = "QL-1110NWB"
    case QL_1115NWB = "QL-1115NWB"
    case PT_D410 = "PT-D410"
    case PT_D460BT = "PT-D460BT"
    case PT_D610BT = "PT-D610BT"
    case PT_D800W = "PT-D800W"
    case PT_E310BT = "PT-E310BT"
    case PT_E510 = "PT-E510"
    case PT_E550W = "PT-E550W"
    case PT_E560BT = "PT-E560BT"
    case PT_E720BT = "PT-E720BT"
    case PT_E800W = "PT-E800W"
    case PT_E850TKW = "PT-E850TKW"
    case PT_E920BT = "PT-E920BT"
    case PT_N25BT = "PT-N25BT"
    case PT_P300BT = "PT-P300BT"
    case PT_P300BTz = "PT-P300BTz"
    case PT_P710BT = "PT-P710BT"
    case PT_P715eBT = "PT-P715eBT"
    case PT_P750W = "PT-P750W"
    case PT_P750Wc = "PT-P750Wc"
    case PT_P900W = "PT-P900W"
    case PT_P910BT = "PT-P910BT"
    case PT_P950NW = "PT-P950NW"
    // swiftlint:enable identifier_name

    /// Modèle proposé par défaut quand on choisit Brother.
    public static let defaultModel = BrotherModel.TD_4550DNWB

    public var id: String { rawValue }

    /// Référence lisible ; la résolution des TD-23xx est mise en évidence.
    public var title: String {
        rawValue
            .replacingOccurrences(of: "_203", with: " (203 dpi)")
            .replacingOccurrences(of: "_300", with: " (300 dpi)")
    }

    public var series: BrotherSeries {
        switch rawValue.prefix(2) {
        case "PJ": return .pj
        case "MW": return .mw
        case "RJ": return .rj
        case "TD": return .td
        case "QL": return .ql
        default: return .pt
        }
    }

    /// Interfaces documentées pour iOS par le manuel du SDK (tableau
    /// « Supported Printer / Print Image »), coches « Android only » exclues.
    /// Vide : aucune interface iOS documentée (USB seul, par exemple).
    ///
    /// Les TD-4410D, TD-4420DN et TD-4520DN n'ont pas de BLE. Le TD-4410D
    /// n'existe pas dans l'énumération du SDK iOS.
    public var connections: Set<BrotherConnection> {
        switch self {
        case .PJ_673, .PJ_773, .RJ_4040, .RJ_3050, .RJ_3150, .RJ_2140,
             .TD_2120N, .TD_2130N, .TD_4420DN, .TD_4520DN,
             .QL_710W, .QL_720NW, .QL_810W,
             .PT_E550W, .PT_P750W, .PT_P750Wc, .PT_D800W, .PT_E800W,
             .PT_E850TKW, .PT_P900W, .PT_P950NW,
             .TD_2125N, .TD_2135N,
             .TD_2320D_203, .TD_2320D_300, .TD_2320DF_203, .TD_2320DF_300,
             .TD_2320DSA_203, .TD_2320DSA_300,
             .TD_4425DN, .TD_4525DN, .TD_4425DNF:
            return [.wifi]
        case .PJ_763MFi, .MW_145MFi, .MW_260MFi, .MW_170, .MW_270,
             .RJ_4030Ai, .PT_E310BT, .PT_E560BT, .PT_E720BT, .PT_E920BT,
             .RJ_2031, .RJ_2131:
            return [.bluetoothClassic]
        case .RJ_3050Ai, .RJ_3150Ai, .RJ_2050, .RJ_2150,
             .QL_820NWB, .QL_1110NWB, .QL_1115NWB:
            return [.wifi, .bluetoothClassic]
        case .RJ_4230B, .RJ_3230B, .RJ_3235B, .RJ_4235B, .PJ_862, .PJ_863:
            return [.bluetoothClassic, .ble]
        case .RJ_4250WB, .RJ_3250WB, .RJ_3255WB, .RJ_4255WB, .PJ_883,
             .TD_4550DNWB, .TD_4455DNWB, .TD_4555DNWB, .TD_4555DNWBF,
             .TD_2125NWB, .TD_2135NWB,
             .TD_2350D_203, .TD_2350D_300, .TD_2350DF_203, .TD_2350DF_300,
             .TD_2350DSA_203, .TD_2350DSA_300, .TD_2350DFSA_203, .TD_2350DFSA_300:
            return [.wifi, .bluetoothClassic, .ble]
        case .PJ_822, .PJ_823, .TD_2030A, .TD_4100N, .TD_4415D,
             .TD_2310D_203, .TD_2310D_300, .PT_E510, .PT_P910BT,
             .PT_D410, .PT_D460BT, .PT_D610BT, .PT_N25BT,
             .PT_P300BT, .PT_P300BTz, .PT_P710BT, .PT_P715eBT:
            return []
        }
    }

    public var supportsBLE: Bool { connections.contains(.ble) }

    /// Interfaces que l'application sait utiliser : BLE puis Wi-Fi.
    public var appConnections: [BrotherConnection] {
        [.ble, .wifi].filter { connections.contains($0) }
    }

    /// Nom de modèle tel que le SDK le renvoie dans
    /// `BRLMChannelExtraInfoKeyModelName`, par exemple « Brother TD-4550DNWB ».
    public var advertisedName: String {
        "Brother " + rawValue
            .replacingOccurrences(of: "_203", with: "")
            .replacingOccurrences(of: "_300", with: "")
    }

    /// Retrouve le modèle d'après le nom renvoyé par la recherche.
    ///
    /// Le nom le plus long l'emporte : « TD-4555DNWBF » n'est pas un
    /// « TD-4555DNWB ». Les TD-23xx existent en 203 et 300 dpi sous le même
    /// nom : la variante 203 dpi est renvoyée, l'utilisateur peut corriger.
    public static func matching(advertisedName name: String) -> BrotherModel? {
        let lowered = name.lowercased()
        return allCases
            .filter { lowered.contains($0.advertisedName.dropFirst("Brother ".count).lowercased()) }
            .max { lhs, rhs in
                if lhs.advertisedName.count != rhs.advertisedName.count {
                    return lhs.advertisedName.count < rhs.advertisedName.count
                }
                return !lhs.rawValue.hasSuffix("_203") && rhs.rawValue.hasSuffix("_203")
            }
    }

    /// Formats tout prêts pour les séries à papier personnalisé (TD, RJ).
    public var paperPresets: [BrotherPaper] {
        guard series.paperSource == .customPaper else { return [] }
        switch String(rawValue.prefix(4)) {
        case "TD-4":
            return [.roll(widthMM: 102), .roll(widthMM: 76), .roll(widthMM: 58),
                    .dieCut(widthMM: 102, lengthMM: 152), .dieCut(widthMM: 102, lengthMM: 51),
                    .dieCut(widthMM: 51, lengthMM: 26), .markRoll(widthMM: 102, lengthMM: 152)]
        case "TD-2":
            return [.roll(widthMM: 58), .roll(widthMM: 51),
                    .dieCut(widthMM: 40, lengthMM: 40), .dieCut(widthMM: 51, lengthMM: 26),
                    .markRoll(widthMM: 58, lengthMM: 40)]
        case "RJ-4":
            return [.roll(widthMM: 102), .roll(widthMM: 58),
                    .dieCut(widthMM: 102, lengthMM: 152), .markRoll(widthMM: 102, lengthMM: 152)]
        case "RJ-3":
            return [.roll(widthMM: 80), .roll(widthMM: 76),
                    .dieCut(widthMM: 76, lengthMM: 44), .markRoll(widthMM: 76, lengthMM: 44)]
        default: // RJ-2
            return [.roll(widthMM: 58), .roll(widthMM: 50),
                    .dieCut(widthMM: 50, lengthMM: 85), .markRoll(widthMM: 58, lengthMM: 85)]
        }
    }

    /// Largeur maximale de papier acceptée, pour borner un format personnalisé.
    public var maxPaperWidthMM: Double {
        switch String(rawValue.prefix(4)) {
        case "TD-4", "RJ-4": return 118
        case "RJ-3": return 80
        default: return 63
        }
    }

    /// Format imposé des MW : A7 pour MW-145MFi et MW-170, A6 sinon.
    public var mwSheetMM: (width: Double, length: Double)? {
        switch self {
        case .MW_145MFi, .MW_170: return (74, 105)
        case .MW_260MFi, .MW_270: return (105, 148)
        default: return nil
        }
    }
}

// MARK: - Papier

public enum BrotherPaperSource: String, Codable, Sendable {
    /// Largeur et longueur libres (`BRLMCustomPaperSize`) : TD, RJ.
    case customPaper
    /// Références DK de `BRLMQLPrintSettingsLabelSize`.
    case qlLabel
    /// Rubans de `BRLMPTPrintSettingsLabelSize`.
    case ptTape
    /// Formats de `BRLMPJPrintSettingsPaperSizeStandard`.
    case pjSheet
    /// Format imposé par le modèle (MW).
    case fixedByModel
}

/// Papier personnalisé des séries TD et RJ, envoyé par `BRLMCustomPaperSize`.
public struct BrotherPaper: Hashable, Codable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        /// Continu (`rollWithTapeWidth`) : la longueur suit le contenu.
        case roll
        /// Prédécoupé (`dieCutWithTapeWidth`) : étiquettes séparées par un espace.
        case dieCut
        /// Marque noire (`markRollWithTapeWidth`) : étiquettes de longueur
        /// fixe repérées par une marque imprimée au dos.
        case markRoll

        public var hasFixedLength: Bool { self != .roll }
    }

    public var kind: Kind
    public var widthMM: Double
    /// Longueur d'une étiquette, ignorée en continu.
    public var lengthMM: Double
    /// Espace entre deux étiquettes (`gapLength`), en prédécoupé.
    public var gapMM: Double
    /// Marge appliquée sur les quatre côtés.
    public var marginMM: Double
    /// `markPosition` : décalage de la marque depuis le début de l'étiquette.
    public var markOffsetMM: Double
    /// `markHeight` : hauteur de la marque noire.
    public var markLengthMM: Double

    public init(kind: Kind, widthMM: Double, lengthMM: Double = 0, gapMM: Double = 0,
                marginMM: Double = 1.5, markOffsetMM: Double = 0, markLengthMM: Double = 0) {
        self.kind = kind
        self.widthMM = widthMM
        self.lengthMM = lengthMM
        self.gapMM = gapMM
        self.marginMM = marginMM
        self.markOffsetMM = markOffsetMM
        self.markLengthMM = markLengthMM
    }

    public static func roll(widthMM: Double) -> BrotherPaper {
        BrotherPaper(kind: .roll, widthMM: widthMM)
    }

    /// Les étiquettes du commerce laissent en général 3 mm entre elles.
    public static func dieCut(widthMM: Double, lengthMM: Double, gapMM: Double = 3) -> BrotherPaper {
        BrotherPaper(kind: .dieCut, widthMM: widthMM, lengthMM: lengthMM, gapMM: gapMM)
    }

    /// Valeurs de départ : marque au début de l'étiquette, 3 mm de haut.
    public static func markRoll(widthMM: Double, lengthMM: Double,
                                markOffsetMM: Double = 0, markLengthMM: Double = 3) -> BrotherPaper {
        BrotherPaper(kind: .markRoll, widthMM: widthMM, lengthMM: lengthMM,
                     markOffsetMM: markOffsetMM, markLengthMM: markLengthMM)
    }

    public var id: String {
        switch kind {
        case .roll: return "roll-\(Self.format(widthMM))"
        case .dieCut: return "diecut-\(Self.format(widthMM))x\(Self.format(lengthMM))-gap\(Self.format(gapMM))"
        case .markRoll:
            return "mark-\(Self.format(widthMM))x\(Self.format(lengthMM))"
                + "-at\(Self.format(markOffsetMM))-h\(Self.format(markLengthMM))"
        }
    }

    /// Change de type en gardant des valeurs plausibles.
    public func converted(to newKind: Kind) -> BrotherPaper {
        var paper = self
        paper.kind = newKind
        if newKind.hasFixedLength, paper.lengthMM <= 0 { paper.lengthMM = paper.widthMM }
        if newKind == .dieCut, paper.gapMM <= 0 { paper.gapMM = 3 }
        if newKind == .markRoll, paper.markLengthMM <= 0 { paper.markLengthMM = 3 }
        paper.markOffsetMM = min(paper.markOffsetMM, max(0, paper.lengthMM))
        return paper
    }

    public var printableWidthMM: Double { max(1, widthMM - marginMM * 2) }
    public var printableLengthMM: Double? { kind.hasFixedLength ? max(1, lengthMM - marginMM * 2) : nil }

    public static func format(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
    }
}

/// Feuille normalisée des PJ.
public enum BrotherSheet: String, CaseIterable, Identifiable, Codable, Sendable {
    case a4, letter, legal, a5

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .a4: return "A4"
        case .letter: return "Letter"
        case .legal: return "Legal"
        case .a5: return "A5"
        }
    }

    public var sizeMM: (width: Double, length: Double) {
        switch self {
        case .a4: return (210, 297)
        case .letter: return (215.9, 279.4)
        case .legal: return (215.9, 355.6)
        case .a5: return (148, 210)
        }
    }
}

/// Étiquette ou ruban d'une énumération du SDK (QL, PT).
///
/// `index` est la valeur brute de l'énumération : les cas y sont déclarés
/// sans valeur explicite, donc numérotés à partir de 0 dans l'ordre de
/// l'en-tête. Garder l'ordre identique à BRLMQLPrintSettings.h et
/// BRLMPTPrintSettings.h.
public struct BrotherLabelSize: Hashable, Sendable, Identifiable {
    public let index: Int
    public let name: String
    public let widthMM: Double
    /// Longueur d'une étiquette prédécoupée, nil pour un rouleau continu.
    public let lengthMM: Double?

    public var id: Int { index }

    public static let ql: [BrotherLabelSize] = make([
        ("DieCutW17H54", 17, 54), ("DieCutW17H87", 17, 87), ("DieCutW23H23", 23, 23),
        ("DieCutW29H42", 29, 42), ("DieCutW29H90", 29, 90), ("DieCutW38H90", 38, 90),
        ("DieCutW39H48", 39, 48), ("DieCutW52H29", 52, 29), ("DieCutW62H29", 62, 29),
        ("DieCutW62H60", 62, 60), ("DieCutW62H75", 62, 75), ("DieCutW62H100", 62, 100),
        ("DieCutW60H86", 60, 86), ("DieCutW54H29", 54, 29), ("DieCutW102H51", 102, 51),
        ("DieCutW102H152", 102, 152), ("DieCutW103H164", 103, 164),
        ("RollW12", 12, nil), ("RollW29", 29, nil), ("RollW38", 38, nil), ("RollW50", 50, nil),
        ("RollW54", 54, nil), ("RollW62", 62, nil), ("RollW62RB", 62, nil), ("RollW102", 102, nil),
        ("RollW103", 103, nil), ("DTRollW90", 90, nil), ("DTRollW102", 102, nil),
        ("DTRollW102H51", 102, 51), ("DTRollW102H152", 102, 152),
        ("RoundW12DIA", 12, 12), ("RoundW24DIA", 24, 24), ("RoundW58DIA", 58, 58)
    ])

    public static let pt: [BrotherLabelSize] = make([
        ("Width3_5mm", 3.5, nil), ("Width6mm", 6, nil), ("Width9mm", 9, nil), ("Width12mm", 12, nil),
        ("Width18mm", 18, nil), ("Width24mm", 24, nil), ("Width36mm", 36, nil),
        ("WidthHS_5_8mm", 5.8, nil), ("WidthHS_8_8mm", 8.8, nil), ("WidthHS_11_7mm", 11.7, nil),
        ("WidthHS_17_7mm", 17.7, nil), ("WidthHS_23_6mm", 23.6, nil), ("WidthFL_21x45mm", 21, 45),
        ("WidthHS_5_2mm", 5.2, nil), ("WidthHS_9_0mm", 9, nil), ("WidthHS_11_2mm", 11.2, nil),
        ("WidthHS_21_0mm", 21, nil), ("WidthHS_31_0mm", 31, nil)
    ])

    private static func make(_ entries: [(String, Double, Double?)]) -> [BrotherLabelSize] {
        entries.enumerated().map { offset, entry in
            BrotherLabelSize(index: offset, name: entry.0, widthMM: entry.1, lengthMM: entry.2)
        }
    }

    public var title: String {
        let width = BrotherPaper.format(widthMM)
        if name.hasPrefix("Round") { return "Ø \(width) mm" }
        if name.hasPrefix("WidthHS") { return "\(width) mm HSe" }
        if name.hasPrefix("WidthFL") { return "21 × 45 mm FLe" }
        if name.hasPrefix("Width") { return "\(width) mm TZe" }
        let prefix = name.hasPrefix("DT") ? "DT " : ""
        let suffix = name.hasSuffix("RB") ? NSLocalizedString(" rouge/noir", comment: "QL two-color roll") : ""
        if let lengthMM {
            return "\(prefix)\(width) × \(BrotherPaper.format(lengthMM)) mm\(suffix)"
        }
        return prefix + String(format: NSLocalizedString("%@ mm continu", comment: "QL continuous roll"), width) + suffix
    }
}

/// Support choisi pour une imprimante Brother.
public enum BrotherMedia: Hashable, Codable, Sendable {
    case custom(BrotherPaper)
    /// Index dans `BrotherLabelSize.ql`.
    case qlLabel(Int)
    /// Index dans `BrotherLabelSize.pt`.
    case ptTape(Int)
    case sheet(BrotherSheet)
    case fixedByModel

    /// Support par défaut d'un modèle. Pour QL et PT, `supported` est la
    /// liste du SDK (`supportedQLLabels`, `supportedPTLabels`) si elle est connue.
    public static func defaultMedia(for model: BrotherModel, supported: Set<Int>? = nil) -> BrotherMedia {
        func pick(_ list: [BrotherLabelSize], preferred: String) -> Int {
            let allowed = list.filter { supported?.contains($0.index) ?? true }
            return (allowed.first { $0.name == preferred } ?? allowed.first ?? list[0]).index
        }
        switch model.series.paperSource {
        case .customPaper: return .custom(model.paperPresets.first ?? .roll(widthMM: 58))
        // DK-22205 : rouleau continu 62 mm, la référence la plus courante.
        case .qlLabel: return .qlLabel(pick(BrotherLabelSize.ql, preferred: "RollW62"))
        case .ptTape: return .ptTape(pick(BrotherLabelSize.pt, preferred: "Width12mm"))
        case .pjSheet: return .sheet(.a4)
        case .fixedByModel: return .fixedByModel
        }
    }

    /// Vrai si ce support convient au modèle.
    public func isCompatible(with model: BrotherModel, supported: Set<Int>? = nil) -> Bool {
        switch (self, model.series.paperSource) {
        case let (.custom(paper), .customPaper):
            return paper.widthMM > 0 && paper.widthMM <= model.maxPaperWidthMM
                && (!paper.kind.hasFixedLength || paper.lengthMM > 0)
        case let (.qlLabel(index), .qlLabel):
            return BrotherLabelSize.ql.indices.contains(index) && (supported?.contains(index) ?? true)
        case let (.ptTape(index), .ptTape):
            return BrotherLabelSize.pt.indices.contains(index) && (supported?.contains(index) ?? true)
        case (.sheet, .pjSheet), (.fixedByModel, .fixedByModel): return true
        default: return false
        }
    }

    /// Zone imprimable approximative en mm. `length` est nil pour un support
    /// continu. Sert à choisir la résolution du rendu : le SDK met de toute
    /// façon l'image à l'échelle de la page (`fitPageAspect`).
    public func printableAreaMM(for model: BrotherModel) -> (width: Double, length: Double?) {
        switch self {
        case let .custom(paper): return (paper.printableWidthMM, paper.printableLengthMM)
        case let .qlLabel(index):
            let label = BrotherLabelSize.ql.indices.contains(index) ? BrotherLabelSize.ql[index] : BrotherLabelSize.ql[22]
            return (label.widthMM, label.lengthMM)
        case let .ptTape(index):
            let tape = BrotherLabelSize.pt.indices.contains(index) ? BrotherLabelSize.pt[index] : BrotherLabelSize.pt[3]
            return (tape.widthMM, tape.lengthMM)
        case let .sheet(sheet): return (sheet.sizeMM.width, sheet.sizeMM.length)
        case .fixedByModel:
            let size = model.mwSheetMM ?? (105, 148)
            return (size.width, size.length)
        }
    }
}

/// Réglages de coupe d'un travail Brother.
///
/// - `autoCut` : coupe après chaque page, ou toutes les
///   `autoCutForEachPageCount` pages ;
/// - `cutAtEnd` : coupe après la dernière page du travail.
///
/// Tout est désactivé par défaut : le massicot des TD est un accessoire, et
/// demander une coupe sans massicot ne coupe rien.
public struct BrotherCutOptions: Hashable, Codable, Sendable {
    public var autoCut: Bool
    /// Pas de coupe, de 1 à 255. Utilisé seulement si `autoCut`.
    public var cutEveryPages: Int
    public var cutAtEnd: Bool

    public init(autoCut: Bool = false, cutEveryPages: Int = 1, cutAtEnd: Bool = false) {
        self.autoCut = autoCut
        self.cutEveryPages = cutEveryPages
        self.cutAtEnd = cutAtEnd
    }

    /// Pas borné à la plage du SDK (`UInt8`, 1 à 255).
    public var clampedCutEveryPages: UInt8 {
        UInt8(clamping: min(255, max(1, cutEveryPages)))
    }

    /// Ne garde que ce que la série sait faire.
    public func restricted(to cutter: BrotherCutterSupport) -> BrotherCutOptions {
        BrotherCutOptions(autoCut: cutter.isControllable && autoCut,
                          cutEveryPages: cutter.supportsCutEvery ? cutEveryPages : 1,
                          cutAtEnd: cutter.supportsCutAtEnd && cutAtEnd)
    }

    public var isAnyCutRequested: Bool { autoCut || cutAtEnd }
}

/// Réglages de rendu transmis au SDK Brother (repris de TD Print Studio).
public struct BrotherQualityOptions: Hashable, Codable, Sendable {
    public enum Halftone: String, Codable, CaseIterable, Sendable {
        case threshold, errorDiffusion, patternDither
    }

    /// De -5 (plus clair) à +5 (plus foncé). `nil` : réglage de l'imprimante.
    /// Pris en compte seulement par les TD (`BRLMTDPrintSettingsDensity`).
    public var density: Int?
    /// `printQuality` : `.best` si vrai, `.fast` sinon.
    public var bestQuality = false
    /// Seuil par défaut : texte et codes-barres nets, sans trame.
    public var halftone: Halftone = .threshold
    /// `halftoneThreshold`, utilisé seulement avec le tramage par seuil.
    public var threshold = 127
    /// Décolleur d'étiquettes (`peelLabel`, accessoire). TD seulement.
    public var peelLabel = false
    /// Marge ajoutée en haut et en bas (`feedDirectionMargins`), en mm. TD seulement.
    public var feedMarginMM = 0.0

    public init() {}

    /// Valeur SDK de `BRLMTDPrintSettingsDensity` : WeakLevel5 (0) à
    /// StrongLevel5 (10), Neutral (5) au milieu ; nil = UsePrinterSetting.
    public var tdDensityRawValue: Int? { density.map { min(5, max(-5, $0)) + 5 } }

    public var clampedThreshold: UInt8 { UInt8(clamping: min(255, max(0, threshold))) }

    /// Marge en points de la tête pour une résolution verticale donnée.
    public func feedMarginDots(ydpi: Double) -> UInt {
        UInt(max(0, (feedMarginMM / 25.4 * (ydpi > 0 ? ydpi : 203)).rounded()))
    }

    // Lecture tolérante : un réglage absent d'une ancienne version garde sa
    // valeur par défaut au lieu d'effacer les autres.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        density = try c.decodeIfPresent(Int.self, forKey: .density)
        bestQuality = try c.decodeIfPresent(Bool.self, forKey: .bestQuality) ?? false
        halftone = try c.decodeIfPresent(Halftone.self, forKey: .halftone) ?? .threshold
        threshold = try c.decodeIfPresent(Int.self, forKey: .threshold) ?? 127
        peelLabel = try c.decodeIfPresent(Bool.self, forKey: .peelLabel) ?? false
        feedMarginMM = try c.decodeIfPresent(Double.self, forKey: .feedMarginMM) ?? 0
    }
}
