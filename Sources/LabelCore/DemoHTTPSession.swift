import Foundation

/// Session HTTP factice (hors ligne) pour le **mode démonstration**, utilisé notamment par
/// la revue App Store : elle répond aux requêtes de la gateway (whoami, articles) avec un
/// catalogue d'articles fictifs, SANS aucun appel réseau. L'app se comporte exactement comme
/// branchée sur une vraie gateway, mais ne dépend d'aucun serveur.
///
/// On réplique ici le comportement du faux serveur de la gateway (filtre `WhereCondition`,
/// tri `OrderByValue`/`OrderByDirection`, pagination `Offset`/`Limit`).
public struct DemoHTTPSession: HTTPSession {
    public init() {}

    public func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let url = request.url
        let path = url?.path ?? ""
        let items = url.map(Self.queryItems) ?? [:]

        let status: Int
        let body: Data

        if path.hasSuffix("/whoami") {
            status = 200
            body = Self.json([
                "app": "EBP Tickets Prix (démo)",
                "account": "Compte de démonstration",
                "folder": ["id": "DEMO", "label": "Société de démonstration"],
            ])
        } else if path.contains("/Items") {
            status = 200
            body = Self.itemsResponse(query: items)
        } else {
            status = 200
            body = Self.json(["data": [], "paging": ["offset": 0, "limit": 0, "total": 0, "returned": 0]])
        }

        let response = HTTPURLResponse(url: url ?? URL(string: "https://demo.local")!,
                                       statusCode: status, httpVersion: nil, headerFields: nil)!
        return (body, response)
    }

    // MARK: - Réponse articles (filtre + tri + pagination)

    private static func itemsResponse(query: [String: String]) -> Data {
        var all = catalog()

        if let condition = query["WhereCondition"], !condition.isEmpty {
            all = applyWhere(all, condition)
        }
        if let orderBy = query["OrderByValue"], !orderBy.isEmpty {
            let desc = (query["OrderByDirection"]?.lowercased() == "descending")
            all = applyOrder(all, field: orderBy, descending: desc)
        }

        let total = all.count
        let offset = max(0, Int(query["Offset"] ?? "0") ?? 0)
        let limitRaw = Int(query["Limit"] ?? "100") ?? 100
        let limit = min(max(limitRaw, 1), 100)
        let page = Array(all.dropFirst(offset).prefix(limit))

        return json([
            "data": page.map { $0.dictionary },
            "paging": ["offset": offset, "limit": limit, "total": total, "returned": page.count],
            "folder": ["id": "DEMO", "label": "Société de démonstration"],
        ])
    }

    // MARK: - Catalogue factice

    /// Un article de démo (sous-ensemble des champs EBP). `dictionary` = JSON prêt à encoder.
    private struct DemoItem {
        let id, caption, family, subFamily, supplier, unit: String
        let priceExcl, priceIncl, vat, realStock, virtualStock, weight, volume: Double
        let barCode: String
        let shelf: String
        let activeState: Int

        var dictionary: [String: Any] {
            [
                "Id": id, "Caption": caption, "DesComClear": caption,
                "SalePriceVatExcluded": String(format: "%.8f", priceExcl),
                "SalePriceVatIncluded": String(format: "%.8f", priceIncl),
                "VatAmount": String(format: "%.8f", vat),
                "BarCode": barCode, "ShelfRef": shelf,
                "FamilyId": family, "SubFamilyId": subFamily,
                "RealStock": String(format: "%.8f", realStock),
                "VirtualStock": String(format: "%.8f", virtualStock),
                "SupplierId": supplier, "UnitId": unit,
                "Weight": String(format: "%.8f", weight),
                "Volume": String(format: "%.8f", volume),
                "ActiveState": activeState,
            ]
        }
    }

    private static func catalog() -> [DemoItem] {
        var items: [DemoItem] = [
            DemoItem(id: "ART001", caption: "Motoréducteur 0,75 kW", family: "FAR00001", subFamily: "SF001",
                     supplier: "FR01066", unit: "UNIT", priceExcl: 420, priceIncl: 504, vat: 84,
                     realStock: 5, virtualStock: 8, weight: 12.5, volume: 0.035,
                     barCode: ean13("366061900001"), shelf: "A-12", activeState: 0),
            DemoItem(id: "ART002", caption: "Chaîne de transmission", family: "FAR00002", subFamily: "SF002",
                     supplier: "FR02210", unit: "ML", priceExcl: 85.5, priceIncl: 102.6, vat: 17.1,
                     realStock: 0, virtualStock: 0, weight: 2.3, volume: 0,
                     barCode: ean13("366061900002"), shelf: "B-04", activeState: 0),
            DemoItem(id: "ART003", caption: "Variateur de fréquence", family: "FAR00001", subFamily: "SF001",
                     supplier: "FR01066", unit: "UNIT", priceExcl: 640, priceIncl: 768, vat: 128,
                     realStock: 12, virtualStock: 15, weight: 4.8, volume: 0.012,
                     barCode: ean13("366061900003"), shelf: "C-01", activeState: 1),
        ]

        let labels = ["Roulement à billes", "Courroie trapézoïdale", "Pignon acier", "Vérin pneumatique",
                      "Capteur inductif", "Moteur asynchrone", "Réducteur à vis", "Accouplement élastique",
                      "Galet tendeur", "Boîtier de dérivation", "Contacteur tripolaire", "Disjoncteur moteur",
                      "Câble souple", "Presse-étoupe", "Joint torique", "Vis sans fin", "Poulie fonte",
                      "Chaîne à rouleaux"]
        let families = ["FAR00001", "FAR00002", "FAR00003", "FAR00004"]
        let subFamilies = ["SF001", "SF002", "SF003"]
        let units = ["UNIT", "ML", "KG", "M"]

        for i in 4...60 {
            let label = labels[(i - 4) % labels.count]
            let priceExcl = Double(10 + (i * 37) % 900)
            let priceIncl = (priceExcl * 1.2 * 100).rounded() / 100
            let stock = (i * 7) % 5 == 0 ? 0.0 : Double((i * 3) % 40)
            let active = i % 11 == 0 ? 1 : 0
            items.append(DemoItem(
                id: String(format: "ART%03d", i),
                caption: "\(label) réf. \(String(format: "%03d", i))",
                family: families[i % families.count], subFamily: subFamilies[i % subFamilies.count],
                supplier: String(format: "FR%05d", 1000 + i % 7), unit: units[i % units.count],
                priceExcl: priceExcl, priceIncl: priceIncl,
                vat: (priceExcl * 0.2 * 100).rounded() / 100,
                realStock: stock, virtualStock: stock + Double(i % 4),
                weight: Double(i % 10) + 0.5, volume: Double(i % 5) / 100,
                barCode: ean13(String(format: "36606190%04d", i)),
                shelf: "\(Character(UnicodeScalar(65 + i % 6)!))-\(String(format: "%02d", i % 20))",
                activeState: active))
        }
        return items
    }

    // MARK: - Filtre / tri (sous-ensemble OData, comme la gateway)

    private static func applyWhere(_ items: [DemoItem], _ whereClause: String) -> [DemoItem] {
        // Conditions séparées par « and », parenthèses ignorées.
        let parts = whereClause.components(separatedBy: " and ")
        var result = items
        for raw in parts {
            let cond = raw.trimmingCharacters(in: CharacterSet(charactersIn: " ()\t"))
            guard !cond.isEmpty else { continue }
            result = result.filter { matches($0, cond) }
        }
        return result
    }

    private static func matches(_ item: DemoItem, _ cond: String) -> Bool {
        // FamilyId eq 'x' / SubFamilyId eq 'x' / BarCode eq 'x'
        if let m = capture(cond, #"^(FamilyId|SubFamilyId|BarCode)\s+eq\s+'(.*)'$"#) {
            switch m[0] {
            case "FamilyId": return item.family == unescape(m[1])
            case "SubFamilyId": return item.subFamily == unescape(m[1])
            default: return item.barCode == unescape(m[1])
            }
        }
        // ActiveState eq N
        if let m = capture(cond, #"^ActiveState\s+eq\s+(-?\d+)$"#) {
            return item.activeState == (Int(m[0]) ?? 0)
        }
        // SalePriceVatIncluded|RealStock ge|le|gt|lt N
        if let m = capture(cond, #"^(SalePriceVatIncluded|RealStock)\s+(ge|le|gt|lt)\s+([0-9.]+)$"#) {
            let actual = m[0] == "RealStock" ? item.realStock : item.priceIncl
            let value = Double(m[2]) ?? 0
            switch m[1] {
            case "ge": return actual >= value
            case "le": return actual <= value
            case "gt": return actual > value
            case "lt": return actual < value
            default: return true
            }
        }
        // contains(Caption|Id,'x')
        if let m = capture(cond, #"^contains\(([A-Za-z]+),'(.*)'\)$"#) {
            let needle = unescape(m[1]).lowercased()
            let hay = (m[0] == "Id" ? item.id : item.caption).lowercased()
            return needle.isEmpty || hay.contains(needle)
        }
        return true   // condition non reconnue : tolérante
    }

    private static func applyOrder(_ items: [DemoItem], field: String, descending: Bool) -> [DemoItem] {
        let numeric = ["SalePriceVatIncluded", "SalePriceVatExcluded", "RealStock"].contains(field)
        let sorted = items.sorted { a, b in
            if numeric {
                return value(a, field) < value(b, field)
            }
            return text(a, field).localizedCaseInsensitiveCompare(text(b, field)) == .orderedAscending
        }
        return descending ? sorted.reversed() : sorted
    }

    private static func value(_ i: DemoItem, _ field: String) -> Double {
        switch field {
        case "SalePriceVatIncluded": return i.priceIncl
        case "SalePriceVatExcluded": return i.priceExcl
        case "RealStock": return i.realStock
        default: return 0
        }
    }

    private static func text(_ i: DemoItem, _ field: String) -> String {
        field == "Caption" ? i.caption : i.id
    }

    // MARK: - Utilitaires

    /// Complète 12 chiffres par la clé de contrôle EAN-13 (codes de démo valides).
    private static func ean13(_ twelve: String) -> String {
        let digits = Array(twelve.prefix(12))
        var sum = 0
        for (idx, ch) in digits.enumerated() {
            sum += (Int(String(ch)) ?? 0) * (idx % 2 == 0 ? 1 : 3)
        }
        let check = (10 - sum % 10) % 10
        return twelve + String(check)
    }

    private static func unescape(_ s: String) -> String { s.replacingOccurrences(of: "''", with: "'") }

    /// Applique un motif regex ancré et renvoie les groupes capturés, ou nil.
    private static func capture(_ text: String, _ pattern: String) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = re.firstMatch(in: text, range: range) else { return nil }
        var groups: [String] = []
        for i in 1..<match.numberOfRanges {
            guard let r = Range(match.range(at: i), in: text) else { groups.append(""); continue }
            groups.append(String(text[r]))
        }
        return groups
    }

    private static func queryItems(_ url: URL) -> [String: String] {
        guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = comps.queryItems else { return [:] }
        var dict: [String: String] = [:]
        for item in items { dict[item.name] = item.value ?? "" }
        return dict
    }

    private static func json(_ object: Any) -> Data {
        (try? JSONSerialization.data(withJSONObject: object)) ?? Data("{}".utf8)
    }
}
