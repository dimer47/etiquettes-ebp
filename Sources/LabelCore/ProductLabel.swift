import Foundation

public struct ProductLabel: Codable, Equatable {
    public var name: String
    public var category: String
    public var shelfReference: String
    public var productReference: String
    public var ean: String
    public var price: String
    public var currency: LabelCurrency
    public var priceCaption: String

    public init(name: String = NSLocalizedString("Spray Acrylique", comment: "Sample product"), category: String = NSLocalizedString("Peinture / Aérosols", comment: "Sample category"), shelfReference: String = NSLocalizedString("RÉF RAYON : 12-04-08", comment: "Sample shelf reference"), productReference: String = "4523187", ean: String = "4006381333931", price: String = "5,95", currency: LabelCurrency = .eur, priceCaption: String = NSLocalizedString("Prix de vente TTC", comment: "Default price caption")) {
        self.name = name; self.category = category; self.shelfReference = shelfReference
        self.productReference = productReference; self.ean = ean; self.price = price; self.currency = currency
        self.priceCaption = priceCaption
    }

    private enum CodingKeys: String, CodingKey {
        case name, category, shelfReference, productReference, ean, price, currency, priceCaption
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        name = try values.decode(String.self, forKey: .name)
        category = try values.decode(String.self, forKey: .category)
        shelfReference = try values.decode(String.self, forKey: .shelfReference)
        productReference = try values.decode(String.self, forKey: .productReference)
        ean = try values.decode(String.self, forKey: .ean)
        price = try values.decode(String.self, forKey: .price)
        currency = try values.decodeIfPresent(LabelCurrency.self, forKey: .currency) ?? .eur
        priceCaption = try values.decodeIfPresent(String.self, forKey: .priceCaption) ?? NSLocalizedString("Prix de vente TTC", comment: "Default price caption")
    }
}

public enum LabelCurrency: String, CaseIterable, Codable, Identifiable {
    case eur = "EUR", usd = "USD", gbp = "GBP", chf = "CHF"
    public var id: String { rawValue }
    public var symbol: String {
        switch self {
        case .eur: "€"
        case .usd: "$"
        case .gbp: "£"
        case .chf: "CHF"
        }
    }
}

public enum PriceFormatter {
    public static func formatted(_ input: String, currency: LabelCurrency = .eur, locale: Locale = .current) -> String? {
        let normalized = input.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "€", with: "")
            .replacingOccurrences(of: currency.symbol, with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: ".")
        guard !normalized.isEmpty, let value = Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX")), value >= 0 else { return nil }
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: value as NSDecimalNumber)
            .map { "\($0.replacingOccurrences(of: "\u{00a0}", with: " ").replacingOccurrences(of: "\u{202f}", with: " ")) \(currency.symbol)" }
    }
}
