import Foundation

/// Un article EBP tel que renvoyé dans `data` par la gateway
/// (`/gescom/api/v1/Items/ItemsExtendedQuery`). On ne décode que le sous-ensemble
/// de champs utiles à l'étiquette ; tout est optionnel car EBP omet les nuls de façon
/// irrégulière. Les montants arrivent en nombres à 8 décimales → `Decimal`.
public struct EBPItem: Decodable, Equatable, Hashable {
    public let id: String?                    // "Id" (à trim)
    public let caption: String?               // "Caption" (libellé)
    public let desComClear: String?           // "DesComClear" (texte propre, à préférer à DesCom RTF)
    public let salePriceVatIncluded: Decimal? // "SalePriceVatIncluded" (TTC)
    public let salePriceVatExcluded: Decimal? // "SalePriceVatExcluded" (HT)
    public let barCode: String?               // "BarCode" (EAN)
    public let shelfRef: String?              // "ShelfRef" (rayon)
    public let familyId: String?              // "FamilyId" (famille)

    /// Identité stable d'une ligne de liste : la référence EBP si présente, sinon le code-barres,
    /// sinon un repli dérivé des champs. Évite les collisions d'`id` dans un ForEach quand des
    /// articles arrivent avec des champs partiels.
    public var rowID: String {
        if let id = id?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty { return "id:" + id }
        if let bc = barCode?.trimmingCharacters(in: .whitespacesAndNewlines), !bc.isEmpty { return "bc:" + bc }
        return "h:\(hashValue)"
    }

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case caption = "Caption"
        case desComClear = "DesComClear"
        case salePriceVatIncluded = "SalePriceVatIncluded"
        case salePriceVatExcluded = "SalePriceVatExcluded"
        case barCode = "BarCode"
        case shelfRef = "ShelfRef"
        case familyId = "FamilyId"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id)
        caption = try c.decodeIfPresent(String.self, forKey: .caption)
        desComClear = try c.decodeIfPresent(String.self, forKey: .desComClear)
        // EBP peut renvoyer les montants en nombre OU en chaîne (ex. "420.00000000").
        salePriceVatIncluded = c.decodeDecimalOrString(forKey: .salePriceVatIncluded)
        salePriceVatExcluded = c.decodeDecimalOrString(forKey: .salePriceVatExcluded)
        // ShelfRef peut arriver en nombre côté EBP : on l'accepte en String ou en Int.
        shelfRef = try c.decodeStringOrNumber(forKey: .shelfRef)
        barCode = try c.decodeIfPresent(String.self, forKey: .barCode)
        familyId = try c.decodeIfPresent(String.self, forKey: .familyId)
    }

    public init(id: String? = nil, caption: String? = nil, desComClear: String? = nil,
                salePriceVatIncluded: Decimal? = nil, salePriceVatExcluded: Decimal? = nil,
                barCode: String? = nil, shelfRef: String? = nil, familyId: String? = nil) {
        self.id = id; self.caption = caption; self.desComClear = desComClear
        self.salePriceVatIncluded = salePriceVatIncluded; self.salePriceVatExcluded = salePriceVatExcluded
        self.barCode = barCode; self.shelfRef = shelfRef; self.familyId = familyId
    }
}

private extension KeyedDecodingContainer {
    /// Décode une valeur qui peut être une String ou un nombre (EBP mélange les deux pour
    /// certains champs comme ShelfRef). Retourne nil si absent.
    func decodeStringOrNumber(forKey key: Key) throws -> String? {
        if let s = try? decodeIfPresent(String.self, forKey: key) { return s }
        if let i = try? decodeIfPresent(Int.self, forKey: key) { return String(i) }
        if let d = try? decodeIfPresent(Decimal.self, forKey: key) { return "\(d)" }
        return nil
    }

    /// Décode un montant qui peut arriver en nombre JSON ou en chaîne ("420.00000000").
    func decodeDecimalOrString(forKey key: Key) -> Decimal? {
        if let d = try? decodeIfPresent(Decimal.self, forKey: key) { return d }
        if let s = try? decodeIfPresent(String.self, forKey: key) { return Decimal(string: s) }
        return nil
    }
}
