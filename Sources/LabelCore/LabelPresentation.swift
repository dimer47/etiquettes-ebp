import Foundation

public enum LabelSize: String, CaseIterable, Identifiable {
    case compact, standard, airy, large

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .compact: NSLocalizedString("Compact", comment: "Label size")
        case .standard: NSLocalizedString("Standard", comment: "Label size")
        case .airy: NSLocalizedString("Rayon aéré", comment: "Label size")
        case .large: NSLocalizedString("Grand", comment: "Label size")
        }
    }
    public var heightDots: Int {
        switch self {
        case .compact: 208
        case .standard: 240
        case .airy: 312
        case .large: 416
        }
    }
    public var heightMillimeters: Int { heightDots / 8 }
}

public enum LabelArrangement: String, CaseIterable, Identifiable {
    case current, priceFirst, columns, barcodeFirst, centered, barcodeLast

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .current: NSLocalizedString("Rayon actuel", comment: "Label arrangement")
        case .priceFirst: NSLocalizedString("Prix en tête", comment: "Label arrangement")
        case .columns: NSLocalizedString("Deux colonnes", comment: "Label arrangement")
        case .barcodeFirst: NSLocalizedString("Code en tête", comment: "Label arrangement")
        case .centered: NSLocalizedString("Centrée", comment: "Label arrangement")
        case .barcodeLast: NSLocalizedString("Code en bas", comment: "Label arrangement")
        }
    }
}
