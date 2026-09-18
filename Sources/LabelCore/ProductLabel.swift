import Foundation

public struct ProductLabel: Codable, Equatable {
    public var name: String
    public var category: String
    public var shelfReference: String
    public var productReference: String
    public var ean: String
    public var price: String

    public init(name: String = "Spray Acrylique", category: String = "Peinture / Aérosols", shelfReference: String = "RÉF RAYON : 12-04-08", productReference: String = "4523187", ean: String = "4006381333931", price: String = "5,95") {
        self.name = name; self.category = category; self.shelfReference = shelfReference
        self.productReference = productReference; self.ean = ean; self.price = price
    }
}

public enum PriceFormatter {
    public static func formatted(_ input: String) -> String? {
        let normalized = input.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "€", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: ".")
        guard !normalized.isEmpty, let value = Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX")), value >= 0 else { return nil }
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.numberStyle = .currency
        formatter.currencyCode = "EUR"
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: value as NSDecimalNumber)?.replacingOccurrences(of: "\u{00a0}", with: " ").replacingOccurrences(of: "\u{202f}", with: " ")
    }
}
