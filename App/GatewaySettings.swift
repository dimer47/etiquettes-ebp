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

    /// Mode démonstration : données factices servies hors ligne (revue App Store, captures,
    /// démo commerciale). Aucune donnée client, aucun serveur requis.
    @Published private(set) var isDemo: Bool

    private let defaults: UserDefaults

    private enum Key {
        static let baseURL = "gateway.baseURL"
        static let pairedSince = "gateway.pairedSince"
        static let demo = "gateway.demoMode"
    }

    /// Config utilisée en mode démo (l'URL n'est jamais réellement appelée : la session démo
    /// répond hors ligne, mais `GatewayConfig` exige une URL/token valides).
    static let demoConfig = GatewayConfig(baseURL: URL(string: "https://demo.local")!, token: "demo")

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.baseURLString = defaults.string(forKey: Key.baseURL) ?? ""
        let paired = defaults.object(forKey: Key.pairedSince) as? Date
        self.pairedSince = paired
        self.isDemo = defaults.bool(forKey: Key.demo)
        var tokenPresent = KeychainToken.get() != nil
        #if DEBUG
        // Pratique de dev : jeton de test injectable via UserDefaults sans clavier ni Keychain.
        if !tokenPresent, let t = defaults.string(forKey: "gateway.debugToken"), !t.isEmpty {
            tokenPresent = true
        }
        #endif
        self.hasToken = tokenPresent

        // Génération automatique des captures (fastlane snapshot) : l'argument de lancement
        // `--uitest-demo` démarre directement en mode démonstration, pour que les tests UI
        // atteignent le catalogue sans passer par l'écran d'appairage. Éphémère : on force
        // l'état en mémoire sans écrire dans UserDefaults, donc aucun effet sur l'app réelle.
        if ProcessInfo.processInfo.arguments.contains("--uitest-demo") {
            self.isDemo = true
            self.pairedSince = Date()
        }
    }

    /// L'app est-elle utilisable : appairée (URL + jeton + date) OU en mode démo.
    var isPaired: Bool {
        isDemo || (currentConfig() != nil && pairedSince != nil)
    }

    /// Config active (démo ou réelle), ou nil si rien n'est configuré.
    func activeConfig() -> GatewayConfig? {
        isDemo ? Self.demoConfig : currentConfig()
    }

    /// Session HTTP à utiliser : stub hors ligne en démo, sinon la vraie session réseau.
    func makeSession() -> HTTPSession {
        isDemo ? DemoHTTPSession() : URLSession.shared
    }

    /// Active le mode démonstration (données factices, hors ligne).
    func startDemo() {
        isDemo = true
        defaults.set(true, forKey: Key.demo)
        markPaired()
    }

    /// Applique un appairage réussi (résultat du claim QR) : stocke l'URL, le jeton et la date.
    /// Désactive le mode démo le cas échéant (on passe à une vraie gateway).
    func applyPairing(endpoint: String, token: String) {
        if isDemo { isDemo = false; defaults.set(false, forKey: Key.demo) }
        baseURLString = endpoint
        setToken(token)
        markPaired()
    }

    /// Marque l'appairage réussi (après un whoami OK).
    func markPaired(date: Date = Date()) {
        pairedSince = date
        defaults.set(date, forKey: Key.pairedSince)
    }

    /// Dissocie la gateway (ou quitte la démo) : efface jeton, URL, date d'appairage et mode démo.
    /// Purge aussi les historiques locaux (articles consultés + impressions) pour qu'aucune
    /// donnée ne fuite d'une session ou d'un compte à l'autre. Les stores étant recréés depuis
    /// `UserDefaults` au prochain appairage, on vide ici la persistance, pas seulement la mémoire.
    func unpair() {
        KeychainToken.delete()
        baseURLString = ""
        defaults.removeObject(forKey: Key.pairedSince)
        defaults.set(false, forKey: Key.demo)
        defaults.removeObject(forKey: ViewedProductStore.storageKey)
        defaults.removeObject(forKey: LabelHistoryStore.storageKey)
        #if DEBUG
        defaults.removeObject(forKey: "gateway.debugToken")
        #endif
        pairedSince = nil
        hasToken = false
        isDemo = false
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
