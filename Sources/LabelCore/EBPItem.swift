import Foundation

/// Un article EBP tel que renvoyé dans `data` par la gateway
/// (`/gescom/api/v1/Items/ItemsExtentedQuery`). On ne décode que le sous-ensemble
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
    public let subFamilyId: String?           // "SubFamilyId" (sous-famille)
    public let vatAmount: Decimal?            // "VatAmount" (montant de TVA sur le prix de vente)
    public let realStock: Decimal?            // "RealStock" (stock réel)
    public let virtualStock: Decimal?         // "VirtualStock" (stock disponible/projeté)
    public let supplierId: String?            // "SupplierId" (fournisseur principal)
    public let unitId: String?                // "UnitId" (unité de vente)
    public let weight: Decimal?               // "Weight" (poids)
    public let volume: Decimal?               // "Volume" (volume)
    public let activeState: Int?              // "ActiveState" (0 = actif chez EBP)

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
        case subFamilyId = "SubFamilyId"
        case vatAmount = "VatAmount"
        case realStock = "RealStock"
        case virtualStock = "VirtualStock"
        case supplierId = "SupplierId"
        case unitId = "UnitId"
        case weight = "Weight"
        case volume = "Volume"
        case activeState = "ActiveState"
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
        subFamilyId = try c.decodeIfPresent(String.self, forKey: .subFamilyId)
        vatAmount = c.decodeDecimalOrString(forKey: .vatAmount)
        realStock = c.decodeDecimalOrString(forKey: .realStock)
        virtualStock = c.decodeDecimalOrString(forKey: .virtualStock)
        supplierId = try c.decodeIfPresent(String.self, forKey: .supplierId)
        unitId = try c.decodeIfPresent(String.self, forKey: .unitId)
        weight = c.decodeDecimalOrString(forKey: .weight)
        volume = c.decodeDecimalOrString(forKey: .volume)
        activeState = try? c.decodeIfPresent(Int.self, forKey: .activeState)
    }

    public init(id: String? = nil, caption: String? = nil, desComClear: String? = nil,
                salePriceVatIncluded: Decimal? = nil, salePriceVatExcluded: Decimal? = nil,
                barCode: String? = nil, shelfRef: String? = nil, familyId: String? = nil,
                subFamilyId: String? = nil, vatAmount: Decimal? = nil,
                realStock: Decimal? = nil, virtualStock: Decimal? = nil,
                supplierId: String? = nil, unitId: String? = nil,
                weight: Decimal? = nil, volume: Decimal? = nil, activeState: Int? = nil) {
        self.id = id; self.caption = caption; self.desComClear = desComClear
        self.salePriceVatIncluded = salePriceVatIncluded; self.salePriceVatExcluded = salePriceVatExcluded
        self.barCode = barCode; self.shelfRef = shelfRef; self.familyId = familyId
        self.subFamilyId = subFamilyId; self.vatAmount = vatAmount
        self.realStock = realStock; self.virtualStock = virtualStock
        self.supplierId = supplierId; self.unitId = unitId
        self.weight = weight; self.volume = volume; self.activeState = activeState
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
