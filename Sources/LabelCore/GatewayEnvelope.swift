import Foundation

/// Enveloppe de réponse de la gateway EBP. La gateway n'expose PAS le corps EBP brut :
/// elle enveloppe les données dans `data`, avec la pagination et le dossier résolu.
public struct GatewayEnvelope<T: Decodable>: Decodable {
    public let data: T
    public let paging: GatewayPaging?
    /// Identifiant du dossier résolu. La gateway le renvoie en objet `{id,label}` (whoami)
    /// ou en simple chaîne (enveloppe de liste) : on accepte les deux et on garde l'id.
    public let folderId: String?
    /// Présent uniquement sur un hit de cache de lecture.
    public let cached: Bool?

    enum CodingKeys: String, CodingKey { case data, paging, folder, cached }

    public init(data: T, paging: GatewayPaging? = nil, folderId: String? = nil, cached: Bool? = nil) {
        self.data = data; self.paging = paging; self.folderId = folderId; self.cached = cached
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        data = try c.decode(T.self, forKey: .data)
        paging = try c.decodeIfPresent(GatewayPaging.self, forKey: .paging)
        cached = try c.decodeIfPresent(Bool.self, forKey: .cached)
        // folder : objet {id,label} OU chaîne OU absent/null.
        if let ref = try? c.decodeIfPresent(GatewayFolderRef.self, forKey: .folder) {
            folderId = ref.id
        } else if let s = try? c.decodeIfPresent(String.self, forKey: .folder) {
            folderId = s
        } else {
            folderId = nil
        }
    }
}

public struct GatewayPaging: Decodable, Equatable {
    public let offset: Int
    public let limit: Int
    public let total: Int
    public let returned: Int

    enum CodingKeys: String, CodingKey { case offset, limit, total, returned }

    public init(offset: Int, limit: Int, total: Int, returned: Int) {
        self.offset = offset; self.limit = limit; self.total = total; self.returned = returned
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        offset = try c.decodeIfPresent(Int.self, forKey: .offset) ?? 0
        limit = try c.decodeIfPresent(Int.self, forKey: .limit) ?? 0
        total = try c.decodeIfPresent(Int.self, forKey: .total) ?? 0
        // `returned` n'est pas toujours renvoyé : on retombe sur total si absent.
        returned = try c.decodeIfPresent(Int.self, forKey: .returned) ?? total
    }
}

/// Dossier EBP résolu, tel que renvoyé par `whoami` et dans l'enveloppe.
public struct GatewayFolderRef: Decodable, Equatable {
    public let id: String
    public let label: String?

    public init(id: String, label: String? = nil) {
        self.id = id; self.label = label
    }
}

/// Réponse de `GET /api/v1/whoami` : contexte résolu pour le jeton.
public struct WhoAmI: Decodable, Equatable {
    public let app: String
    public let account: String
    public let folder: GatewayFolderRef?

    public init(app: String, account: String, folder: GatewayFolderRef? = nil) {
        self.app = app; self.account = account; self.folder = folder
    }
}

// MARK: - Asynchrone (202 + jobs)

/// Corps d'un `202 Accepted` : la lecture a basculé en job.
public struct GatewayJobAccepted: Decodable, Equatable {
    public let jobId: String
    public let status: JobState
    public let pollIntervalHint: Double?

    public init(jobId: String, status: JobState, pollIntervalHint: Double? = nil) {
        self.jobId = jobId; self.status = status; self.pollIntervalHint = pollIntervalHint
    }
}

/// État d'un job (`GET /api/v1/jobs/{id}`).
public struct GatewayJobStatus: Decodable, Equatable {
    public let jobId: String
    public let status: JobState
    public let pollIntervalHint: Double?

    public init(jobId: String, status: JobState, pollIntervalHint: Double? = nil) {
        self.jobId = jobId; self.status = status; self.pollIntervalHint = pollIntervalHint
    }
}

/// Résultat d'un job terminé (`GET /api/v1/jobs/{id}/result`).
public struct GatewayJobResult<T: Decodable>: Decodable {
    public let jobId: String
    public let status: JobState
    public let result: T?
    public let errors: [String]?

    public init(jobId: String, status: JobState, result: T? = nil, errors: [String]? = nil) {
        self.jobId = jobId; self.status = status; self.result = result; self.errors = errors
    }
}

public enum JobState: String, Decodable, Equatable {
    case pending, running, done, partial, failed

    /// Le job est-il dans un état terminal (plus rien à attendre) ?
    public var isTerminal: Bool { self == .done || self == .partial || self == .failed }
}

// MARK: - Erreurs

public enum GatewayError: Error, Equatable {
    case unauthorized(String)     // 401 { message }
    case forbidden(String)        // 403 { message }
    case folderRequired(String)   // 400 { error: "folder_required", message }
    case badRequest(String)       // autre 400
    case http(Int)                // autre code HTTP
    case jobFailed([String])      // job terminé en failed
    case jobTimedOut              // dépassement du délai de polling
    case decoding(String)         // DecodingError, résumé pour diagnostic
    case transport(String)        // URLError, résumé (reste Equatable)
    case invalidConfig            // URL/jeton manquant ou invalide

    /// Construit l'erreur à partir du corps d'erreur de la gateway et du code HTTP.
    /// La gateway renvoie `{ "error": "...", "message": "..." }` ou `{ "message": "..." }`.
    public static func decode(status: Int, body: Data) -> GatewayError {
        let parsed = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
        let message = (parsed?["message"] as? String) ?? ""
        let errorCode = parsed?["error"] as? String

        switch status {
        case 401: return .unauthorized(message)
        case 403: return .forbidden(message)
        case 400 where errorCode == "folder_required": return .folderRequired(message)
        case 400: return .badRequest(message)
        default: return .http(status)
        }
    }
}
