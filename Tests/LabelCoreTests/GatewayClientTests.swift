import XCTest
@testable import LabelCore

/// Session HTTP factice : renvoie des réponses scénarisées selon le chemin,
/// et enregistre les requêtes reçues (pour vérifier l'auth et les paramètres).
private actor StubSession: HTTPSession {
    struct Response { let status: Int; let body: Data }
    /// File de réponses à servir dans l'ordre d'appel.
    private var queue: [Response]
    private(set) var requests: [URLRequest] = []

    init(_ responses: [Response]) { self.queue = responses }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        let next = queue.isEmpty ? Response(status: 500, body: Data()) : queue.removeFirst()
        let http = HTTPURLResponse(url: request.url!, statusCode: next.status, httpVersion: nil, headerFields: nil)!
        return (next.body, http)
    }

    func recordedRequests() -> [URLRequest] { requests }
}

private func json(_ s: String) -> Data { Data(s.utf8) }
private let baseURL = URL(string: "http://192.0.2.10:8088")!
private let config = GatewayConfig(baseURL: baseURL, token: "gw_test")
private let noWait: @Sendable (Double) async -> Void = { _ in }

final class GatewayClientTests: XCTestCase {

    func testItemsSynchronous200() async throws {
        let stub = StubSession([
            .init(status: 200, body: json(#"""
            { "data": [ { "Id": "A", "Caption": "Article A" } ],
              "paging": { "offset": 0, "limit": 50, "total": 1, "returned": 1 } }
            """#))
        ])
        let client = GatewayClient(config: config, session: stub, sleep: noWait)
        let page = try await client.items(ItemsQuery(search: "art"))

        XCTAssertEqual(page.items.count, 1)
        XCTAssertEqual(page.items.first?.caption, "Article A")
        XCTAssertFalse(page.hasMore)

        // Vérifie l'en-tête d'auth et les paramètres attendus.
        let req = await stub.recordedRequests().first!
        XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer gw_test")
        let url = req.url!.absoluteString
        XCTAssertTrue(url.contains("/gescom/api/v1/Items/ItemsExtendedQuery"))
        XCTAssertTrue(url.contains("OrderByValue=Id"))
        XCTAssertTrue(url.contains("WhereCondition="))
        XCTAssertFalse(url.contains("FolderId"))   // jamais envoyé
    }

    func testItemsAsync202ThenPoll() async throws {
        let stub = StubSession([
            // 1er appel : 202 accepté
            .init(status: 202, body: json(#"{ "jobId": "j1", "status": "pending", "pollIntervalHint": 0 }"#)),
            // sondage statut : running
            .init(status: 200, body: json(#"{ "jobId": "j1", "status": "running" }"#)),
            // sondage statut : done
            .init(status: 200, body: json(#"{ "jobId": "j1", "status": "done" }"#)),
            // résultat
            .init(status: 200, body: json(#"""
            { "jobId": "j1", "status": "done",
              "result": [ { "Id": "B", "Caption": "Article B" } ], "errors": null }
            """#)),
        ])
        let client = GatewayClient(config: config, session: stub, sleep: noWait)
        let page = try await client.items(ItemsQuery())

        XCTAssertEqual(page.items.count, 1)
        XCTAssertEqual(page.items.first?.id, "B")
    }

    func testItemsJobFailedThrows() async throws {
        let stub = StubSession([
            .init(status: 202, body: json(#"{ "jobId": "j2", "status": "pending", "pollIntervalHint": 0 }"#)),
            .init(status: 200, body: json(#"{ "jobId": "j2", "status": "failed" }"#)),
            .init(status: 200, body: json(#"{ "jobId": "j2", "status": "failed", "result": null, "errors": ["Quota EBP"] }"#)),
        ])
        let client = GatewayClient(config: config, session: stub, sleep: noWait)
        do {
            _ = try await client.items(ItemsQuery())
            XCTFail("doit lever jobFailed")
        } catch GatewayError.jobFailed(let errors) {
            XCTAssertEqual(errors, ["Quota EBP"])
        }
    }

    func testUnauthorizedThrows() async throws {
        let stub = StubSession([
            .init(status: 401, body: json(#"{ "message": "Jeton d'application invalide ou révoqué." }"#))
        ])
        let client = GatewayClient(config: config, session: stub, sleep: noWait)
        do {
            _ = try await client.items(ItemsQuery())
            XCTFail("doit lever unauthorized")
        } catch GatewayError.unauthorized(let message) {
            XCTAssertEqual(message, "Jeton d'application invalide ou révoqué.")
        }
    }

    func testWhoami() async throws {
        let stub = StubSession([
            .init(status: 200, body: json(#"""
            { "app": "Logiciel tickets", "account": "Atelier Démo", "folder": { "id": "1001", "label": "Société Démo" } }
            """#))
        ])
        let client = GatewayClient(config: config, session: stub, sleep: noWait)
        let who = try await client.whoami()
        XCTAssertEqual(who.app, "Logiciel tickets")
        XCTAssertEqual(who.account, "Atelier Démo")
        XCTAssertEqual(who.folder?.label, "Société Démo")

        let req = await stub.recordedRequests().first!
        XCTAssertTrue(req.url!.absoluteString.hasSuffix("/api/v1/whoami"))
        XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer gw_test")
    }

    func testPagingHasMore() {
        let page = ItemsPage(items: [], paging: GatewayPaging(offset: 0, limit: 50, total: 120, returned: 50))
        XCTAssertTrue(page.hasMore)
        let last = ItemsPage(items: [], paging: GatewayPaging(offset: 100, limit: 50, total: 120, returned: 20))
        XCTAssertFalse(last.hasMore)
    }
}
