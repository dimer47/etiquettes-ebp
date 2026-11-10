import SwiftUI

/// Écran d'accueil / connexion à la gateway EBP, affiché tant que l'app n'est pas appairée.
/// Esthétique « bienvenue » : logo, message, bouton « Se connecter » qui ouvre le scanner de
/// QR d'appairage. Le QR encode `{ endpoint, pairingCode }` ; on échange le code contre le jeton.
/// Un second bouton (« Se connecter manuellement ») ouvre la saisie URL + jeton, toujours
/// disponible : on favorise le QR, mais la saisie reste un recours.
struct PairingView: View {
    @ObservedObject var settings: GatewaySettings

    @State private var showingScanner = false
    @State private var claiming = false
    @State private var errorMessage: String?
    @State private var showingManual = false

    var body: some View {
        ZStack {
            // Fond dégradé discret.
            LinearGradient(colors: [Color.accentColor.opacity(0.18), Color(.systemBackground)],
                           startPoint: .top, endPoint: .center)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                logo

                VStack(spacing: 10) {
                    Text(NSLocalizedString("Bienvenue", comment: "Welcome"))
                        .font(.largeTitle.weight(.bold))
                    Text(NSLocalizedString("Connectez cette application à la gateway EBP pour accéder à vos articles et imprimer vos étiquettes.", comment: "Welcome subtitle"))
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                Spacer()

                if claiming {
                    ProgressView(NSLocalizedString("Appairage en cours…", comment: "Pairing in progress"))
                        .padding(.bottom, 8)
                }

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote).foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                VStack(spacing: 14) {
                    Button {
                        errorMessage = nil
                        showingScanner = true
                    } label: {
                        Label(NSLocalizedString("Se connecter", comment: "Connect"), systemImage: "qrcode.viewfinder")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(claiming)

                    Button {
                        errorMessage = nil
                        showingManual = true
                    } label: {
                        Text(NSLocalizedString("Se connecter manuellement", comment: "Manual connect"))
                            .font(.subheadline.weight(.medium))
                    }
                    .disabled(claiming)

                    Text(NSLocalizedString("Scannez le QR code fourni par votre administrateur.", comment: "QR hint"))
                        .font(.caption).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 2)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
        .sheet(isPresented: $showingScanner) { scannerSheet }
        .sheet(isPresented: $showingManual) { manualSheet }
    }

    /// Logo de l'application (le même asset que l'icône d'app, « base article »),
    /// posé sur une pastille bleue aux couleurs de la gateway.
    private var logo: some View {
        ZStack {
            Circle().fill(Color.accentColor.gradient).frame(width: 110, height: 110)
            Image("AppLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 66, height: 66)
        }
        .shadow(color: .accentColor.opacity(0.3), radius: 16, y: 8)
    }

    private var scannerSheet: some View {
        NavigationStack {
            ZStack {
                QRScannerView(
                    onFound: { raw in handleScanned(raw) },
                    onError: { message in
                        showingScanner = false
                        errorMessage = message
                    }
                )
                .ignoresSafeArea(edges: .bottom)

                // Cadre de visée.
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(.white.opacity(0.9), lineWidth: 3)
                    .frame(width: 240, height: 240)
                    .allowsHitTesting(false)
            }
            .navigationTitle(NSLocalizedString("Scanner le QR", comment: "Scan QR"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("Annuler", comment: "Cancel")) { showingScanner = false }
                }
            }
        }
    }

    /// QR scanné → parse → claim → stocke le jeton et bascule sur la liste.
    private func handleScanned(_ raw: String) {
        showingScanner = false
        guard let payload = PairingPayload.decode(fromQRString: raw) else {
            errorMessage = NSLocalizedString("QR invalide. Demandez un nouveau QR et réessayez.", comment: "Invalid QR")
            return
        }
        claiming = true
        Task { @MainActor in
            do {
                let result = try await PairingClient().claim(payload)
                settings.applyPairing(endpoint: result.endpoint, token: result.token)  // bascule isPaired
            } catch {
                errorMessage = Self.message(for: error)
            }
            claiming = false
        }
    }

    private static func message(for error: Error) -> String {
        guard let e = error as? PairingError else { return error.localizedDescription }
        switch e {
        case .invalidQR: return NSLocalizedString("QR invalide. Demandez un nouveau QR et réessayez.", comment: "Invalid QR")
        case .codeExpired: return NSLocalizedString("Ce QR n’est plus valide. Demandez-en un nouveau.", comment: "Expired QR")
        case .rateLimited: return NSLocalizedString("Trop de tentatives. Patientez un instant puis réessayez.", comment: "Rate limited")
        case .badRequest(let m): return m.isEmpty ? NSLocalizedString("Requête refusée.", comment: "") : m
        case .http(let code): return String(format: NSLocalizedString("Erreur HTTP %d.", comment: ""), code)
        case .decoding: return NSLocalizedString("Réponse illisible de la gateway.", comment: "")
        case .transport(let m): return String(format: NSLocalizedString("Gateway injoignable : %@", comment: ""), m)
        }
    }

    // MARK: - Connexion manuelle

    @State private var manualURL = ""
    @State private var manualToken = ""
    @State private var manualError: String?
    @State private var manualTesting = false

    /// Saisie manuelle soignée : explication, carte URL + jeton, bouton Appairer en pleine largeur.
    /// Teste la connexion (whoami) avant de valider l'appairage.
    private var manualSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(NSLocalizedString("Connexion manuelle", comment: "Manual connection"))
                            .font(.title2.weight(.bold))
                        Text(NSLocalizedString("Cette application fonctionne avec la gateway EBP. Renseignez l’adresse de la gateway et votre jeton d’application pour vous connecter.", comment: "Manual connection help"))
                            .font(.subheadline).foregroundStyle(.secondary)
                    }

                    VStack(spacing: 0) {
                        TextField(NSLocalizedString("Adresse de la gateway (https://…)", comment: "Gateway URL"), text: $manualURL)
                            .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                            .padding()
                        Divider().padding(.leading)
                        SecureField(NSLocalizedString("Jeton d’application (gw_…)", comment: "App token"), text: $manualToken)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .padding()
                    }
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))

                    if let manualError {
                        Label(manualError, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote).foregroundStyle(.red)
                    }

                    Button {
                        testAndPair()
                    } label: {
                        HStack {
                            if manualTesting { ProgressView().tint(.white) }
                            Text(manualTesting
                                 ? NSLocalizedString("Connexion…", comment: "Connecting")
                                 : NSLocalizedString("Appairer", comment: "Pair"))
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(manualURL.isEmpty || manualToken.isEmpty || manualTesting)

                    Text(NSLocalizedString("Astuce : la connexion par QR code est plus simple. Demandez le QR à votre administrateur pour éviter cette saisie.", comment: "Manual hint QR"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(NSLocalizedString("Connexion manuelle", comment: "Manual connection"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button(NSLocalizedString("Fermer", comment: "Close")) { showingManual = false } }
            .onAppear { if manualURL.isEmpty { manualURL = settings.baseURLString } }
        }
    }

    /// Teste le couple URL + jeton (whoami) avant d'enregistrer l'appairage.
    private func testAndPair() {
        manualError = nil
        let trimmed = manualURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), url.scheme != nil, url.host != nil else {
            manualError = NSLocalizedString("Adresse invalide.", comment: "Invalid URL")
            return
        }
        manualTesting = true
        let config = GatewayConfig(baseURL: url, token: manualToken.trimmingCharacters(in: .whitespacesAndNewlines))
        Task { @MainActor in
            do {
                _ = try await GatewayClient(config: config).whoami()
                settings.applyPairing(endpoint: trimmed, token: config.token)  // bascule isPaired
            } catch {
                manualError = EBPSearchModel.message(for: error)
            }
            manualTesting = false
        }
    }
}
