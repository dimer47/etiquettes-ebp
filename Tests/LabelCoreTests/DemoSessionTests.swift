import XCTest
@testable import LabelCore

/// Vérifie que le mode démo (session hors ligne) sert bien les articles et applique
/// filtre / tri / pagination, sans aucun réseau.
final class DemoSessionTests: XCTestCase {

    // Config de démo (URL/token factices, jamais réellement appelés par la session stub).
    private let demoConfig = GatewayConfig(baseURL: URL(string: "https://demo.local")!, token: "demo")

    private func demoClient() -> GatewayClient {
        GatewayClient(config: demoConfig, session: DemoHTTPSession())
    }

    func testDemoWhoami() async throws {
        let who = try await demoClient().whoami()
        XCTAssertEqual(who.account, "Compte de démonstration")
        XCTAssertEqual(who.folder?.id, "DEMO")
    }

    func testDemoFirstPageFull() async throws {
        let page = try await demoClient().items(ItemsQuery(offset: 0, limit: 100))
        XCTAssertEqual(page.paging?.total, 60)       // catalogue de 60 articles
        XCTAssertEqual(page.items.count, 60)         // limit 100 → tout tient
        XCTAssertEqual(page.items.first?.caption, "Motoréducteur 0,75 kW")
    }

    func testDemoPagination() async throws {
        let client = demoClient()
        let p1 = try await client.items(ItemsQuery(offset: 0, limit: 50))
        XCTAssertEqual(p1.items.count, 50)
        XCTAssertEqual(p1.paging?.total, 60)
        let p2 = try await client.items(ItemsQuery(offset: 50, limit: 50))
        XCTAssertEqual(p2.items.count, 10)
    }

    func testDemoFilterInStock() async throws {
        let page = try await demoClient().items(ItemsQuery(offset: 0, limit: 100, inStockOnly: true))
        XCTAssertEqual(page.paging?.total, 47)        // cohérent avec la gateway
        XCTAssertTrue(page.items.allSatisfy { ($0.realStock ?? 0) > 0 })
    }

    func testDemoSortByPriceDescending() async throws {
        let page = try await demoClient().items(
            ItemsQuery(offset: 0, limit: 5, orderBy: "SalePriceVatIncluded", orderDescending: true))
        let prices = page.items.compactMap { $0.salePriceVatIncluded }
        XCTAssertEqual(prices, prices.sorted(by: >))   // décroissant
    }

    func testDemoBarcodeLookup() async throws {
        let client = demoClient()
        let found = try await client.itemByBarcode("3660619000029")
        XCTAssertEqual(found?.caption, "Chaîne de transmission")
        let missing = try await client.itemByBarcode("0000000000000")
        XCTAssertNil(missing)
    }
}
