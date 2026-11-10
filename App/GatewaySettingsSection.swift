import SwiftUI

/// Section « Gateway EBP » du panneau Réglages : état de l'appairage (sans jamais afficher le jeton),
/// test de connexion et dissociation.
struct GatewaySettingsSection: View {
    @ObservedObject var settings: GatewaySettings

    @State private var testState: GatewayTestState = .idle

    var body: some View {
        Section("Gateway EBP") {
            LabeledContent {
                Label(NSLocalizedString("Connectée", comment: "Gateway connected"), systemImage: "checkmark.circle.fill")
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(.green)
            } label: {
                Text(NSLocalizedString("État", comment: "State"))
            }

            if let since = settings.pairedSince {
                LabeledContent(
                    NSLocalizedString("Depuis", comment: "Connected since"),
                    value: since.formatted(date: .abbreviated, time: .shortened)
                )
            }

            Button {
                GatewayConnectionTester.test(settings: settings) { testState = $0 }
            } label: {
                HStack {
                    Text(NSLocalizedString("Tester la connexion", comment: "Test connection"))
                    if testState == .running { Spacer(); ProgressView() }
                }
            }
            .disabled(testState == .running)

            GatewayTestResultView(state: testState)

            Button(NSLocalizedString("Dissocier", comment: "Unpair"), role: .destructive) {
                settings.unpair()
            }
        }
    }
}

/// État d'un test de connexion à la gateway (partagé par les Réglages et l'appairage).
enum GatewayTestState: Equatable {
    case idle, running
    case ok(app: String, account: String, folder: String?)
    case failed(String)
    case invalidConfig
}

/// Lance un whoami et renvoie l'état résultant. Logique partagée Réglages / appairage.
enum GatewayConnectionTester {
    @MainActor
    static func test(settings: GatewaySettings, update: @escaping (GatewayTestState) -> Void) {
        guard let config = settings.activeConfig() else { update(.invalidConfig); return }
        let session = settings.makeSession()
        update(.running)
        Task { @MainActor in
            do {
                let who = try await GatewayClient(config: config, session: session).whoami()
                update(.ok(app: who.app, account: who.account, folder: who.folder?.label))
            } catch {
                update(.failed(EBPSearchModel.message(for: error)))
            }
        }
    }
}

/// Affichage inline du résultat d'un test de connexion.
struct GatewayTestResultView: View {
    let state: GatewayTestState

    var body: some View {
        switch state {
        case .ok(let app, let account, let folder):
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(NSLocalizedString("Connecté", comment: "Connected")).font(.footnote.weight(.semibold))
                    Text("\(app) · \(account)\(folder.map { " · \($0)" } ?? "")")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } icon: { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
        case .failed(let message):
            Label(message, systemImage: "xmark.circle.fill")
                .font(.caption).foregroundStyle(.red)
        case .invalidConfig:
            Label(NSLocalizedString("Renseignez une URL valide et un jeton.", comment: "Invalid config"),
                  systemImage: "exclamationmark.circle")
                .font(.caption).foregroundStyle(.orange)
        case .idle, .running:
            EmptyView()
        }
    }
}
