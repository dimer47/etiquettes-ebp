import SwiftUI

/// Feuille d'IMPORT par scan de QR : réutilise le scanner existant (`QRScannerView`), puis confie
/// la chaîne décodée à `onScanned`. Le parent valide le payload et renvoie un message de résultat
/// (succès ou erreur) qui s'affiche ici. Même cadre de visée que l'appairage, pour la cohérence.
struct ImportScanView: View {
    let title: String
    let hint: String
    /// Reçoit la chaîne brute du QR, renvoie un message à afficher (succès → vert, échec → rouge).
    /// Retourne `true` en cas de succès (la feuille se ferme après un court délai).
    let onScanned: (String) -> ImportOutcome
    let onClose: () -> Void

    @State private var outcome: ImportOutcome?
    @State private var handled = false

    var body: some View {
        NavigationStack {
            ZStack {
                QRScannerView(
                    onFound: { raw in handle(raw) },
                    onError: { message in outcome = .failure(message) }
                )
                .ignoresSafeArea(edges: .bottom)

                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(.white.opacity(0.9), lineWidth: 3)
                    .frame(width: 240, height: 240)
                    .allowsHitTesting(false)

                VStack {
                    Spacer()
                    Text(hint)
                        .font(.footnote).foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(12)
                        .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal, 24)
                    if let outcome {
                        Label(outcome.message, systemImage: outcome.isSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(outcome.isSuccess ? .green : .red)
                            .padding(12)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                            .padding(.horizontal, 24)
                        if !outcome.isSuccess {
                            Button(NSLocalizedString("Réessayer", comment: "Retry scan")) {
                                self.outcome = nil
                                handled = false
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    Spacer().frame(height: 40)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("Annuler", comment: "Cancel"), action: onClose)
                }
            }
        }
    }

    private func handle(_ raw: String) {
        guard !handled else { return }
        handled = true
        let result = onScanned(raw)
        outcome = result
        if result.isSuccess {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.1))
                onClose()
            }
        }
    }
}

/// Résultat d'un import, avec le message à montrer à l'utilisateur.
struct ImportOutcome {
    let isSuccess: Bool
    let message: String

    static func success(_ message: String) -> ImportOutcome { ImportOutcome(isSuccess: true, message: message) }
    static func failure(_ message: String) -> ImportOutcome { ImportOutcome(isSuccess: false, message: message) }
}

// MARK: - Messages d'erreur d'import

extension ShareDecodeError {
    /// Message clair et court en français pour l'utilisateur.
    var userMessage: String {
        switch self {
        case .notJSON:
            return NSLocalizedString("Ce code ne contient pas de donnée reconnue par l’app.", comment: "Import error notJSON")
        case .unsupportedVersion:
            return NSLocalizedString("Ce partage vient d’une version plus récente de l’app. Mettez l’app à jour.", comment: "Import error version")
        case .wrongKind:
            return NSLocalizedString("Ce partage ne correspond pas à ce qui est attendu ici.", comment: "Import error wrong kind")
        case .empty:
            return NSLocalizedString("Rien à importer dans ce partage.", comment: "Import error empty")
        case .malformed:
            return NSLocalizedString("Partage illisible ou incomplet.", comment: "Import error malformed")
        }
    }
}
