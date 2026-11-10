import Foundation

/// Résultat du mapping d'un article EBP vers une étiquette.
/// - `label` : le ProductLabel imprimable (TTC seulement sur l'étiquette).
/// - `priceExclVat` : le HT formaté, affiché à l'écran uniquement (jamais imprimé).
/// - `eanWasInvalid` : vrai si le BarCode EBP n'a pas passé la validation EAN-13
///   (il est alors stocké brut, sans être rejeté).
/// Informations additionnelles d'un article, affichées à l'écran uniquement (jamais imprimées).
/// Tous les champs sont optionnels : absents si EBP ne les renseigne pas.
public struct ProductDetails: Equatable, Hashable {
    public let vatAmount: String?       // montant de TVA formaté (ex. "100,80")
    public let vatRatePercent: String?  // taux de TVA déduit (ex. "20")
    public let realStock: String?       // stock réel (ex. "12")
    public let virtualStock: String?    // stock disponible/projeté
    public let supplierId: String?      // fournisseur principal
    public let unitId: String?          // unité de vente
    public let weight: String?          // poids formaté
    public let volume: String?          // volume formaté
    public let subFamilyId: String?     // sous-famille
    public let isActive: Bool?          // état actif (ActiveState == 0)

    public init(vatAmount: String? = nil, vatRatePercent: String? = nil,
                realStock: String? = nil, virtualStock: String? = nil,
                supplierId: String? = nil, unitId: String? = nil,
                weight: String? = nil, volume: String? = nil,
                subFamilyId: String? = nil, isActive: Bool? = nil) {
        self.vatAmount = vatAmount; self.vatRatePercent = vatRatePercent
        self.realStock = realStock; self.virtualStock = virtualStock
        self.supplierId = supplierId; self.unitId = unitId
        self.weight = weight; self.volume = volume
        self.subFamilyId = subFamilyId; self.isActive = isActive
    }

    /// Vrai si au moins une info est présente (sinon on masque les blocs correspondants).
    public var hasAny: Bool {
        vatAmount != nil || realStock != nil || virtualStock != nil || supplierId != nil
            || unitId != nil || weight != nil || volume != nil || subFamilyId != nil || isActive != nil
    }
}

public struct MappedProduct: Equatable, Hashable, Identifiable {
    public let label: ProductLabel
    public let priceExclVat: String?
    public let eanWasInvalid: Bool
    public let details: ProductDetails

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

    public init(label: ProductLabel, priceExclVat: String?, eanWasInvalid: Bool,
                details: ProductDetails = ProductDetails()) {
        self.label = label; self.priceExclVat = priceExclVat
        self.eanWasInvalid = eanWasInvalid; self.details = details
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

        let details = mapDetails(item, ttcValue: item.salePriceVatIncluded,
                                 htValue: item.salePriceVatExcluded, locale: locale)
        return MappedProduct(label: label, priceExclVat: ht, eanWasInvalid: eanWasInvalid, details: details)
    }

    /// Construit les infos additionnelles (écran only) à partir de l'article EBP.
    private static func mapDetails(_ item: EBPItem, ttcValue: Decimal?, htValue: Decimal?,
                                   locale: Locale) -> ProductDetails {
        // TVA : montant fourni par EBP. Un montant explicite (même 0, article exonéré) est
        // affiché ; seul un champ absent (nil) masque la ligne.
        let vatAmount = item.vatAmount.map { formatted($0, locale: locale) }
        let vatRate = vatRatePercent(vatAmount: item.vatAmount, ht: htValue, ttc: ttcValue)

        let isActive = item.activeState.map { $0 == 0 }

        return ProductDetails(
            vatAmount: vatAmount,
            vatRatePercent: vatRate,
            realStock: item.realStock.map { quantity($0, locale: locale) },
            virtualStock: item.virtualStock.map { quantity($0, locale: locale) },
            supplierId: (item.supplierId?.trimmed).nonEmpty,
            unitId: (item.unitId?.trimmed).nonEmpty,
            weight: item.weight.flatMap { $0 == 0 ? nil : quantity($0, locale: locale) },
            volume: item.volume.flatMap { $0 == 0 ? nil : quantity($0, locale: locale) },
            subFamilyId: (item.subFamilyId?.trimmed).nonEmpty,
            isActive: isActive
        )
    }

    /// Taux de TVA en pourcentage (entier si rond), déduit du montant de TVA et du HT.
    /// Repli : (TTC−HT)/HT si le montant n'est pas fourni. nil si indéterminable.
    private static func vatRatePercent(vatAmount: Decimal?, ht: Decimal?, ttc: Decimal?) -> String? {
        guard let ht, ht > 0 else { return nil }
        let amount: Decimal?
        if let vatAmount { amount = vatAmount }   // montant explicite (y compris 0 → taux 0 %)
        else if let ttc, ttc > ht { amount = ttc - ht }
        else { amount = nil }
        guard let amount else { return nil }

        let rate = (amount / ht) * 100
        var r = rate, rounded = Decimal()
        NSDecimalRound(&rounded, &r, 1, .plain)   // 1 décimale
        let f = NumberFormatter()
        f.locale = Locale(identifier: "fr_FR"); f.numberStyle = .decimal
        f.minimumFractionDigits = 0; f.maximumFractionDigits = 1
        return f.string(from: rounded as NSDecimalNumber)
    }

    /// Formate une quantité : entier si rond, sinon jusqu'à 3 décimales.
    private static func quantity(_ value: Decimal, locale: Locale) -> String {
        let f = NumberFormatter()
        f.locale = locale; f.numberStyle = .decimal
        f.minimumFractionDigits = 0; f.maximumFractionDigits = 3
        return f.string(from: value as NSDecimalNumber) ?? "\(value)"
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
