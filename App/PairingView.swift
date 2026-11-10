import SwiftUI

/// Écran d'appairage de la gateway EBP, affiché au démarrage tant que l'app n'est pas appairée.
///
/// Le scan de QR d'appairage sera branché quand le back-office d'appairage sera prêt — ici c'est
/// une zone désactivée « bientôt disponible ». En attendant, une section de développement permet
/// de saisir manuellement l'URL et le jeton pour appairer via `whoami`.
struct PairingView: View {
    @ObservedObject var settings: GatewaySettings

    @State private var tokenField = ""
    @State private var testState: GatewayTestState = .idle

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    header

                    qrPlaceholder

                    developmentSection
                }
                .padding()
            }
            .navigationTitle(NSLocalizedString("Appairage", comment: "Pairing"))
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "qrcode.viewfinder")
                .font(.system(size: 52))
                .foregroundStyle(.tint)
            Text(NSLocalizedString("Appairer la gateway EBP", comment: "Pair the EBP gateway"))
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
            Text(NSLocalizedString("Scannez le QR code d’appairage fourni par le back-office.",
                                   comment: "Pairing instruction"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 24)
    }

    /// Zone de scan QR désactivée (le scan réel arrivera avec le back-office d'appairage).
    private var qrPlaceholder: some View {
        VStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8]))
                .foregroundStyle(.secondary.opacity(0.4))
                .frame(height: 220)
                .overlay {
                    VStack(spacing: 8) {
                        Image(systemName: "qrcode.viewfinder").font(.system(size: 40))
                        Text(NSLocalizedString("Scan du QR — bientôt disponible",
                                               comment: "QR scan coming soon"))
                            .font(.footnote)
                    }
                    .foregroundStyle(.secondary)
                }
            Text(NSLocalizedString("Le scan sera activé une fois le back-office d’appairage en place.",
                                   comment: "QR coming soon note"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    /// Saisie manuelle temporaire (développement) : URL + jeton, puis « Tester et appairer ».
    private var developmentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(NSLocalizedString("Développement", comment: "Development"))
                .font(.headline)

            TextField(NSLocalizedString("URL de la gateway", comment: "Gateway URL"),
                      text: $settings.baseURLString)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)

            SecureField(NSLocalizedString("Jeton d’app (gw_…)", comment: "App token"),
                        text: $tokenField)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)

            Button {
                pair()
            } label: {
                HStack {
                    Text(NSLocalizedString("Tester et appairer", comment: "Test and pair"))
                    if testState == .running { Spacer(); ProgressView() }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(testState == .running || !canPair)

            GatewayTestResultView(state: testState)
        }
        .padding()
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 16))
    }

    private var canPair: Bool {
        !settings.baseURLString.trimmingCharacters(in: .whitespaces).isEmpty
            && (!tokenField.trimmingCharacters(in: .whitespaces).isEmpty || settings.hasToken)
    }

    /// Enregistre le jeton saisi, teste la connexion (whoami) et, en cas de succès, marque l'appairage.
    private func pair() {
        let trimmedToken = tokenField.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedToken.isEmpty { settings.setToken(trimmedToken) }

        guard let config = settings.currentConfig() else { testState = .invalidConfig; return }
        testState = .running
        Task { @MainActor in
            do {
                let who = try await GatewayClient(config: config).whoami()
                testState = .ok(app: who.app, account: who.account, folder: who.folder?.label)
                tokenField = ""
                settings.markPaired()   // bascule isPaired → RootView affiche la liste
            } catch {
                testState = .failed(EBPSearchModel.message(for: error))
            }
        }
    }
}
