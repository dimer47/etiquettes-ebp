import Foundation

public struct ProductLabel: Codable, Equatable, Hashable {
    public var name: String
    public var category: String
    public var shelfReference: String
    public var productReference: String
    public var ean: String
    public var price: String
    public var currency: LabelCurrency
    public var priceCaption: String
    /// Date de génération de l'étiquette, posée au moment d'imprimer ou de prévisualiser.
    /// Optionnelle : nil pour les étiquettes qui n'affichent pas de date (et pour les
    /// données sauvegardées avant l'ajout de ce champ → rétro-compatible au décodage).
    public var generatedAt: Date?

    // Champs additionnels bindables sur un modèle perso. Tous optionnels (nil = EBP ne les
    // renseigne pas) et DÉJÀ FORMATÉS par `EBPProductMapper` (jamais la valeur brute EBP) :
    // les prix portent devise + 2 décimales, les quantités sont nettoyées de leurs zéros.
    // Codable rétro-compatible : absents des données sauvegardées avant leur ajout.
    public var priceExclVat: String?   // SalePriceVatExcluded, formaté monnaie (ex. « 420,00 € »)
    public var vatAmount: String?      // VatAmount, formaté monnaie
    public var realStock: String?      // RealStock, quantité nettoyée (ex. « 5 »)
    public var virtualStock: String?   // VirtualStock, quantité nettoyée
    public var subFamily: String?      // SubFamilyId (code tel quel)
    public var supplier: String?       // SupplierId (code tel quel, ex. « FR01066 »)
    public var unit: String?           // UnitId (UNIT, ML, KG, M…)
    public var weight: String?         // Weight, quantité nettoyée (ex. « 12,5 »)
    public var volume: String?         // Volume, quantité nettoyée

    public init(name: String = NSLocalizedString("Spray Acrylique", comment: "Sample product"), category: String = NSLocalizedString("Peinture / Aérosols", comment: "Sample category"), shelfReference: String = NSLocalizedString("RÉF RAYON : 12-04-08", comment: "Sample shelf reference"), productReference: String = "4523187", ean: String = "4006381333931", price: String = "5,95", currency: LabelCurrency = .eur, priceCaption: String = NSLocalizedString("Prix de vente TTC", comment: "Default price caption"), generatedAt: Date? = nil,
                priceExclVat: String? = nil, vatAmount: String? = nil, realStock: String? = nil, virtualStock: String? = nil, subFamily: String? = nil, supplier: String? = nil, unit: String? = nil, weight: String? = nil, volume: String? = nil) {
        self.name = name; self.category = category; self.shelfReference = shelfReference
        self.productReference = productReference; self.ean = ean; self.price = price; self.currency = currency
        self.priceCaption = priceCaption; self.generatedAt = generatedAt
        self.priceExclVat = priceExclVat; self.vatAmount = vatAmount
        self.realStock = realStock; self.virtualStock = virtualStock
        self.subFamily = subFamily; self.supplier = supplier; self.unit = unit
        self.weight = weight; self.volume = volume
    }

    private enum CodingKeys: String, CodingKey {
        case name, category, shelfReference, productReference, ean, price, currency, priceCaption, generatedAt
        case priceExclVat, vatAmount, realStock, virtualStock, subFamily, supplier, unit, weight, volume
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
        generatedAt = try values.decodeIfPresent(Date.self, forKey: .generatedAt)
        priceExclVat = try values.decodeIfPresent(String.self, forKey: .priceExclVat)
        vatAmount = try values.decodeIfPresent(String.self, forKey: .vatAmount)
        realStock = try values.decodeIfPresent(String.self, forKey: .realStock)
        virtualStock = try values.decodeIfPresent(String.self, forKey: .virtualStock)
        subFamily = try values.decodeIfPresent(String.self, forKey: .subFamily)
        supplier = try values.decodeIfPresent(String.self, forKey: .supplier)
        unit = try values.decodeIfPresent(String.self, forKey: .unit)
        weight = try values.decodeIfPresent(String.self, forKey: .weight)
        volume = try values.decodeIfPresent(String.self, forKey: .volume)
    }

    /// Date de génération formatée au format par défaut « 11/05/2026 15:17:00 ».
    public var generatedAtText: String? {
        generatedAt.map { LabelDateFormatter.text(for: $0, pattern: nil) }
    }

    /// Date de génération formatée selon un pattern DateFormatter donné (nil = format par défaut).
    public func generatedAtFormatted(pattern: String?) -> String? {
        generatedAt.map { LabelDateFormatter.text(for: $0, pattern: pattern) }
    }
}

/// Formatage de la date de génération sur les étiquettes.
///
/// Le modèle stocke un pattern DateFormatter (Unicode, ex. "dd/MM/yyyy"). L'éditeur propose
/// des presets prêts à l'emploi et un format personnalisé saisi en tokens simples
/// (JJ, MM, AAAA, HH, mm, ss) traduits ici en pattern Unicode.
public enum LabelDateFormatter {
    /// Pattern utilisé quand aucun format n'est choisi.
    public static let defaultPattern = "dd/MM/yyyy HH:mm:ss"

    public static func text(for date: Date, pattern: String?) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = (pattern?.isEmpty == false ? pattern! : defaultPattern)
        return f.string(from: date)
    }

    /// Un preset de format proposé dans l'éditeur : un libellé en tokens simples et le pattern réel.
    public struct Preset: Equatable, Identifiable, Sendable {
        public let label: String     // ex. "JJ/MM/AAAA HH:mm"
        public let pattern: String   // ex. "dd/MM/yyyy HH:mm"
        public var id: String { pattern }
    }

    /// Liste de formats prêts, libellés en tokens français lisibles.
    public static let presets: [Preset] = [
        Preset(label: "JJ/MM", pattern: "dd/MM"),
        Preset(label: "JJ/MM/AAAA", pattern: "dd/MM/yyyy"),
        Preset(label: "JJ/MM/AAAA HH:mm", pattern: "dd/MM/yyyy HH:mm"),
        Preset(label: "JJ/MM/AAAA HH:mm:ss", pattern: "dd/MM/yyyy HH:mm:ss"),
        Preset(label: "HH:mm", pattern: "HH:mm"),
        Preset(label: "HH:mm:ss", pattern: "HH:mm:ss"),
        Preset(label: "AAAA-MM-JJ", pattern: "yyyy-MM-dd"),
        Preset(label: "AAAA-MM-JJ HH:mm:ss", pattern: "yyyy-MM-dd HH:mm:ss"),
        Preset(label: "JJ-MM-AAAA", pattern: "dd-MM-yyyy"),
        Preset(label: "MM/AAAA", pattern: "MM/yyyy"),
    ]

    /// Convertit un motif en tokens simples (JJ MM AAAA HH mm ss) vers un pattern DateFormatter.
    /// JJ→dd, MM→MM (mois), AAAA→yyyy, HH→HH (24 h), mm→mm (minutes), ss→ss. Les autres
    /// caractères (séparateurs /, -, :, espaces) sont conservés tels quels.
    public static func pattern(fromTokens tokens: String) -> String {
        var result = ""
        var rest = Substring(tokens)
        // Remplacement glouton, du token le plus long au plus court, pour éviter les collisions.
        let rules: [(String, String)] = [("AAAA", "yyyy"), ("JJ", "dd"), ("MM", "MM"),
                                          ("HH", "HH"), ("mm", "mm"), ("ss", "ss")]
        outer: while let first = rest.first {
            for (token, replacement) in rules where rest.hasPrefix(token) {
                result += replacement
                rest = rest.dropFirst(token.count)
                continue outer
            }
            result.append(first)
            rest = rest.dropFirst()
        }
        return result
    }

    /// Convertit un pattern DateFormatter vers des tokens simples lisibles (pour pré-remplir le
    /// champ « format personnalisé » depuis un pattern stocké).
    public static func tokens(fromPattern pattern: String) -> String {
        var result = pattern
        for (token, p) in [("AAAA", "yyyy"), ("JJ", "dd"), ("MM", "MM"),
                           ("HH", "HH"), ("mm", "mm"), ("ss", "ss")] {
            result = result.replacingOccurrences(of: p, with: token)
        }
        return result
    }
}

public enum LabelCurrency: String, CaseIterable, Codable, Identifiable, Hashable {
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
