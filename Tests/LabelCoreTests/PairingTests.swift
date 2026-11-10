import XCTest
@testable import LabelCore

private actor PairingStubSession: HTTPSession {
    struct Response { let status: Int; let body: Data }
    private var queue: [Response]
    private(set) var requests: [URLRequest] = []
    init(_ responses: [Response]) { self.queue = responses }
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        let next = queue.isEmpty ? Response(status: 500, body: Data()) : queue.removeFirst()
        let http = HTTPURLResponse(url: request.url!, statusCode: next.status, httpVersion: nil, headerFields: nil)!
        return (next.body, http)
    }
    func recorded() -> [URLRequest] { requests }
}

private func json(_ s: String) -> Data { Data(s.utf8) }

final class PairingTests: XCTestCase {

    // MARK: - Décodage du QR

    func testQRDecodingValid() {
        let raw = #"{ "endpoint": "https://gw.example.com", "pairingCode": "abc123" }"#
        let payload = PairingPayload.decode(fromQRString: raw)
        XCTAssertEqual(payload?.endpoint.absoluteString, "https://gw.example.com")
        XCTAssertEqual(payload?.pairingCode, "abc123")
    }

    func testQRDecodingInvalidJSON() {
        XCTAssertNil(PairingPayload.decode(fromQRString: "pas du json"))
    }

    func testQRDecodingMissingFields() {
        XCTAssertNil(PairingPayload.decode(fromQRString: #"{ "endpoint": "https://gw.example.com" }"#))
        XCTAssertNil(PairingPayload.decode(fromQRString: #"{ "pairingCode": "abc" }"#))
        XCTAssertNil(PairingPayload.decode(fromQRString: #"{ "endpoint": "pas-une-url", "pairingCode": "abc" }"#))
        XCTAssertNil(PairingPayload.decode(fromQRString: #"{ "endpoint": "https://gw.example.com", "pairingCode": "" }"#))
    }

    // MARK: - Claim

    private let payload = PairingPayload(endpoint: URL(string: "https://gw.example.com")!, pairingCode: "code48")

    func testClaimSuccess() async throws {
        let stub = PairingStubSession([
            .init(status: 200, body: json(#"{ "token": "gw_abc", "endpoint": "https://gw.example.com", "app": "Appli iOS" }"#))
        ])
        let result = try await PairingClient(session: stub).claim(payload)
        XCTAssertEqual(result.token, "gw_abc")
        XCTAssertEqual(result.app, "Appli iOS")

        let req = await stub.recorded().first!
        XCTAssertEqual(req.httpMethod, "POST")
        XCTAssertTrue(req.url!.absoluteString.hasSuffix("/api/v1/pairing/claim"))
    }

    func testClaimExpired() async {
        let stub = PairingStubSession([
            .init(status: 410, body: json(#"{ "message": "Code d'appairage invalide ou expiré." }"#))
        ])
        do { _ = try await PairingClient(session: stub).claim(payload); XCTFail("doit lever codeExpired") }
        catch PairingError.codeExpired(let m) { XCTAssertEqual(m, "Code d'appairage invalide ou expiré.") }
        catch { XCTFail("mauvaise erreur : \(error)") }
    }

    func testClaimRateLimited() async {
        let stub = PairingStubSession([.init(status: 429, body: Data())])
        do { _ = try await PairingClient(session: stub).claim(payload); XCTFail("doit lever rateLimited") }
        catch PairingError.rateLimited {}
        catch { XCTFail("mauvaise erreur : \(error)") }
    }

    func testClaimRejectsInsecureEndpoint() async {
        // Un endpoint HTTP non-local doit être refusé AVANT tout appel réseau.
        let stub = PairingStubSession([.init(status: 200, body: Data())])
        let payload = PairingPayload(endpoint: URL(string: "http://gateway.example.com")!, pairingCode: "ABC")
        do { _ = try await PairingClient(session: stub).claim(payload); XCTFail("doit lever insecureEndpoint") }
        catch PairingError.insecureEndpoint {}
        catch { XCTFail("mauvaise erreur : \(error)") }
        let count = await stub.requests.count
        XCTAssertEqual(count, 0)   // aucun appel réseau n'a été fait
    }

    func testIsSecureEndpoint() {
        XCTAssertTrue(PairingClient.isSecureEndpoint(URL(string: "https://gw.example.com")!))
        XCTAssertTrue(PairingClient.isSecureEndpoint(URL(string: "http://localhost:8088")!))
        XCTAssertTrue(PairingClient.isSecureEndpoint(URL(string: "http://127.0.0.1:8088")!))
        XCTAssertTrue(PairingClient.isSecureEndpoint(URL(string: "http://mac.local:8088")!))
        // Un hôte HTTP public (non local) est toujours refusé, DEBUG ou non.
        XCTAssertFalse(PairingClient.isSecureEndpoint(URL(string: "http://gateway.example.com")!))
        // En DEBUG, une IP LAN privée est tolérée (test sur appareil réel) ; pas en release.
        #if DEBUG
        XCTAssertTrue(PairingClient.isSecureEndpoint(URL(string: "http://192.168.0.175:8088")!))
        #else
        XCTAssertFalse(PairingClient.isSecureEndpoint(URL(string: "http://192.168.0.175:8088")!))
        #endif
    }

    func testPrivateLANAddressDetection() {
        XCTAssertTrue(PairingClient.isPrivateLANAddress("192.168.0.175"))
        XCTAssertTrue(PairingClient.isPrivateLANAddress("10.0.0.5"))
        XCTAssertTrue(PairingClient.isPrivateLANAddress("172.16.3.4"))
        XCTAssertFalse(PairingClient.isPrivateLANAddress("172.32.0.1"))  // hors 16-31
        XCTAssertFalse(PairingClient.isPrivateLANAddress("8.8.8.8"))     // public
        XCTAssertFalse(PairingClient.isPrivateLANAddress("gateway.example.com"))
    }

    func testEBPItemRowIDIsStableAndFallsBack() {
        XCTAssertEqual(EBPItem(id: " ART001 ").rowID, "id:ART001")
        XCTAssertEqual(EBPItem(barCode: "3660619000012").rowID, "bc:3660619000012")
        // Sans réf ni code-barres : repli déterministe (pas de collision avec un autre contenu).
        let a = EBPItem(caption: "A").rowID
        let b = EBPItem(caption: "B").rowID
        XCTAssertNotEqual(a, b)
    }
}
