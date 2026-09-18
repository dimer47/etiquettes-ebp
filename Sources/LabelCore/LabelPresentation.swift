public enum LabelSize: String, CaseIterable, Identifiable {
    case compact, standard, airy, large

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .compact: "Compact"
        case .standard: "Standard"
        case .airy: "Rayon aéré"
        case .large: "Grand"
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
        case .current: "Rayon actuel"
        case .priceFirst: "Prix en tête"
        case .columns: "Deux colonnes"
        case .barcodeFirst: "Code en tête"
        case .centered: "Centrée"
        case .barcodeLast: "Code en bas"
        }
    }
}
