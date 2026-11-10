import SwiftUI

/// Racine de l'application : décide de l'écran selon l'état d'appairage de la gateway.
///  - non appairé → `PairingView` (appairage, scan QR à venir + saisie dev).
///  - appairé → `ContentView` (liste des articles EBP + impression), qui reçoit la config gateway.
struct RootView: View {
    @StateObject private var gateway = GatewaySettings()

    var body: some View {
        if gateway.isPaired {
            ContentView(gateway: gateway)
        } else {
            PairingView(settings: gateway)
        }
    }
}
