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
}
