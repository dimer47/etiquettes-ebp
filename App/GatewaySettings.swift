import Foundation

/// Configuration de connexion à la gateway EBP, conservée comme les autres préférences :
/// l'URL de base dans `UserDefaults`, le jeton `gw_…` dans le trousseau (jamais en clair
/// dans un plist ni dans une propriété publiée).
@MainActor
final class GatewaySettings: ObservableObject {
    @Published var baseURLString: String {
        didSet { defaults.set(baseURLString, forKey: Key.baseURL) }
    }

    /// Reflet de la présence d'un jeton (pour piloter l'UI) ; la valeur réelle reste au trousseau.
    @Published private(set) var hasToken: Bool

    /// Date d'appairage réussi (whoami OK). Nil tant que l'app n'est pas appairée.
    @Published private(set) var pairedSince: Date?

    private let defaults: UserDefaults

    private enum Key {
        static let baseURL = "gateway.baseURL"
        static let pairedSince = "gateway.pairedSince"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.baseURLString = defaults.string(forKey: Key.baseURL) ?? ""
        let paired = defaults.object(forKey: Key.pairedSince) as? Date
        self.pairedSince = paired
        var tokenPresent = KeychainToken.get() != nil
        #if DEBUG
        // Pratique de dev : jeton de test injectable via UserDefaults sans clavier ni Keychain.
        if !tokenPresent, let t = defaults.string(forKey: "gateway.debugToken"), !t.isEmpty {
            tokenPresent = true
        }
        #endif
        self.hasToken = tokenPresent
    }

    /// L'app est-elle appairée : config valide (URL + jeton) ET date d'appairage enregistrée.
    var isPaired: Bool {
        currentConfig() != nil && pairedSince != nil
    }

    /// Applique un appairage réussi (résultat du claim QR) : stocke l'URL, le jeton et la date.
    func applyPairing(endpoint: String, token: String) {
        baseURLString = endpoint
        setToken(token)
        markPaired()
    }

    /// Marque l'appairage réussi (après un whoami OK).
    func markPaired(date: Date = Date()) {
        pairedSince = date
        defaults.set(date, forKey: Key.pairedSince)
    }

    /// Dissocie la gateway : efface jeton, URL et date d'appairage.
    func unpair() {
        KeychainToken.delete()
        baseURLString = ""
        defaults.removeObject(forKey: Key.pairedSince)
        #if DEBUG
        defaults.removeObject(forKey: "gateway.debugToken")
        #endif
        pairedSince = nil
        hasToken = false
    }

    /// Enregistre le jeton au trousseau et met à jour l'indicateur.
    func setToken(_ token: String) {
        KeychainToken.set(token)
        hasToken = KeychainToken.get() != nil
    }

    /// Efface le jeton.
    func clearToken() {
        KeychainToken.delete()
        hasToken = false
    }

    /// Construit la config si l'URL est valide et un jeton présent ; nil sinon.
    func currentConfig() -> GatewayConfig? {
        let trimmed = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), url.scheme != nil, url.host != nil else { return nil }
        var token = KeychainToken.get()
        #if DEBUG
        // Repli dev : le Keychain peut être indisponible sur simulateur non signé.
        if token == nil { token = defaults.string(forKey: "gateway.debugToken") }
        #endif
        guard let token, !token.isEmpty else { return nil }
        return GatewayConfig(baseURL: url, token: token)
    }
}
