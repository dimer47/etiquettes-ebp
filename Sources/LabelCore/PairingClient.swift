import Foundation

/// Contenu décodé d'un QR d'appairage : l'URL de base de la gateway + le code à usage unique.
/// Le QR encode un JSON `{ "endpoint": "...", "pairingCode": "..." }`.
public struct PairingPayload: Equatable, Sendable {
    public let endpoint: URL
    public let pairingCode: String

    public init(endpoint: URL, pairingCode: String) {
        self.endpoint = endpoint; self.pairingCode = pairingCode
    }

    /// Décode le contenu brut d'un QR. Renvoie nil si le format est invalide
    /// (JSON cassé, champs manquants, URL invalide).
    public static func decode(fromQRString raw: String) -> PairingPayload? {
        guard let data = raw.data(using: .utf8),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let endpointString = json["endpoint"] as? String,
              let code = json["pairingCode"] as? String,
              !code.isEmpty,
              let url = URL(string: endpointString.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme != nil, url.host != nil else {
            return nil
        }
        return PairingPayload(endpoint: url, pairingCode: code)
    }
}

/// Résultat d'un appairage réussi : le jeton d'app, l'endpoint et le libellé de l'app.
public struct PairingResult: Decodable, Equatable, Sendable {
    public let token: String
    public let endpoint: String
    public let app: String

    public init(token: String, endpoint: String, app: String) {
        self.token = token; self.endpoint = endpoint; self.app = app
    }
}

public enum PairingError: Error, Equatable {
    case invalidQR                 // QR illisible / mauvais format
    case insecureEndpoint          // endpoint non-HTTPS (code en clair refusé)
    case codeExpired(String)       // 410 : code invalide, expiré ou déjà utilisé
    case rateLimited               // 429 : trop de tentatives
    case badRequest(String)        // 422 : corps invalide
    case http(Int)                 // autre code HTTP
    case decoding(String)
    case transport(String)

    public static func decode(status: Int, body: Data) -> PairingError {
        let message = ((try? JSONSerialization.jsonObject(with: body)) as? [String: Any])?["message"] as? String ?? ""
        switch status {
        case 410: return .codeExpired(message)
        case 429: return .rateLimited
        case 422: return .badRequest(message)
        default: return .http(status)
        }
    }
}

/// Client d'appairage : échange un code (lu dans un QR) contre un jeton d'app, via la gateway.
/// Endpoint public (pas d'auth) : `POST {endpoint}/api/v1/pairing/claim { "code": "..." }`.
public struct PairingClient: Sendable {
    private let session: HTTPSession

    public init(session: HTTPSession = URLSession.shared) {
        self.session = session
    }

    /// Réclame le jeton à partir du contenu d'un QR.
    /// Exige HTTPS (le code à usage unique ne doit jamais partir en clair), sauf vers un hôte
    /// de développement local (localhost / 127.0.0.1 / *.local).
    public func claim(_ payload: PairingPayload) async throws -> PairingResult {
        guard Self.isSecureEndpoint(payload.endpoint) else { throw PairingError.insecureEndpoint }

        let url = payload.endpoint.appendingPathComponent("api/v1/pairing/claim")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let body = try? JSONSerialization.data(withJSONObject: ["code": payload.pairingCode]) else {
            throw PairingError.badRequest("")
        }
        request.httpBody = body

        let data: Data, response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw PairingError.transport(error.localizedDescription)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw PairingError.decode(status: status, body: data) }

        do { return try JSONDecoder().decode(PairingResult.self, from: data) }
        catch { throw PairingError.decoding(error.localizedDescription) }
    }

    /// Un endpoint est sûr s'il est en HTTPS, ou en HTTP vers un hôte de développement local
    /// (localhost, 127.0.0.1, ::1, ou un nom en .local). En build DEBUG, on tolère aussi une
    /// adresse IP du réseau local privé (LAN), pour tester l'appairage par QR sur un appareil
    /// réel sans TLS. En production (release), seul HTTPS est accepté hors hôte local.
    static func isSecureEndpoint(_ url: URL) -> Bool {
        switch url.scheme?.lowercased() {
        case "https": return true
        case "http":
            let host = (url.host ?? "").lowercased()
            if host == "localhost" || host == "127.0.0.1" || host == "::1" || host.hasSuffix(".local") {
                return true
            }
            #if DEBUG
            return isPrivateLANAddress(host)
            #else
            return false
            #endif
        default: return false
        }
    }

    /// Vrai si l'hôte est une adresse IPv4 d'une plage privée (RFC 1918) : 10/8, 172.16/12,
    /// 192.168/16. Utilisé seulement en DEBUG pour autoriser un test LAN par QR.
    static func isPrivateLANAddress(_ host: String) -> Bool {
        let parts = host.split(separator: ".")
        guard parts.count == 4, let a = Int(parts[0]), let b = Int(parts[1]),
              parts.allSatisfy({ Int($0) != nil }) else { return false }
        if a == 10 { return true }
        if a == 192, b == 168 { return true }
        if a == 172, (16...31).contains(b) { return true }
        return false
    }
}
