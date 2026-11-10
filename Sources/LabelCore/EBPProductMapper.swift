import Foundation

/// Résultat du mapping d'un article EBP vers une étiquette.
/// - `label` : le ProductLabel imprimable (TTC seulement sur l'étiquette).
/// - `priceExclVat` : le HT formaté, affiché à l'écran uniquement (jamais imprimé).
/// - `eanWasInvalid` : vrai si le BarCode EBP n'a pas passé la validation EAN-13
///   (il est alors stocké brut, sans être rejeté).
public struct MappedProduct: Equatable, Hashable, Identifiable {
    public let label: ProductLabel
    public let priceExclVat: String?
    public let eanWasInvalid: Bool

    /// Identité stable pour la navigation SwiftUI : référence + code-barres, avec repli sur le
    /// nom puis le prix, pour qu'un article sans réf ni EAN n'entre pas en collision tout en
    /// restant déterministe (même article → même id).
    public var id: String {
        let ref = label.productReference.trimmingCharacters(in: .whitespacesAndNewlines)
        let ean = label.ean.trimmingCharacters(in: .whitespacesAndNewlines)
        if !ref.isEmpty || !ean.isEmpty { return ref + "|" + ean }
        let name = label.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return "x|" + name + "|" + label.price
    }

    public init(label: ProductLabel, priceExclVat: String?, eanWasInvalid: Bool) {
        self.label = label; self.priceExclVat = priceExclVat; self.eanWasInvalid = eanWasInvalid
    }
}

public enum EBPProductMapper {
    /// Transforme un article EBP en étiquette. Ne rejette jamais un article : un code-barres
    /// invalide est conservé brut (signalé par `eanWasInvalid`), à charge de l'UI d'avertir.
    public static func map(_ item: EBPItem, locale: Locale = Locale(identifier: "fr_FR")) -> MappedProduct {
        let name = (item.desComClear?.trimmed).nonEmpty
            ?? (item.caption?.trimmed).nonEmpty
            ?? ""

        // Prix : montants EBP en 8 décimales → arrondis à 2 décimales, formatés localement.
        let ttc = item.salePriceVatIncluded.map { formatted($0, locale: locale) } ?? ""
        let ht = item.salePriceVatExcluded.map { formatted($0, locale: locale) }

        // EAN : on tente de compléter/valider ; si ça échoue, on garde la valeur brute.
        let rawBarcode = (item.barCode?.trimmed) ?? ""
        var ean = rawBarcode
        var eanWasInvalid = false
        if !rawBarcode.isEmpty {
            if let valid = try? EAN13.completed(rawBarcode) {
                ean = valid
            } else {
                ean = rawBarcode
                eanWasInvalid = true
            }
        }

        let label = ProductLabel(
            name: name,
            category: (item.familyId?.trimmed) ?? "",
            shelfReference: (item.shelfRef?.trimmed) ?? "",
            productReference: (item.id?.trimmed) ?? "",
            ean: ean,
            price: ttc,
            currency: .eur,
            priceCaption: NSLocalizedString("Prix de vente TTC", comment: "Default price caption")
        )

        return MappedProduct(label: label, priceExclVat: ht, eanWasInvalid: eanWasInvalid)
    }

    /// Arrondit à 2 décimales (half-up) et formate sans symbole monétaire
    /// (le modèle/formatteur ajoutent la devise à l'affichage).
    private static func formatted(_ value: Decimal, locale: Locale) -> String {
        var input = value
        var rounded = Decimal()
        NSDecimalRound(&rounded, &input, 2, .plain)
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: rounded as NSDecimalNumber) ?? "\(rounded)"
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

private extension Optional where Wrapped == String {
    /// Renvoie la chaîne si elle n'est ni nil ni vide, sinon nil.
    var nonEmpty: String? {
        guard let self, !self.isEmpty else { return nil }
        return self
    }
}
