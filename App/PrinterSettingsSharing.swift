import SwiftUI
import PocketPrinter5890Kit

/// Pont entre les réglages imprimante vivants de l'app (`PrinterSetup` + `PrinterManager`) et le
/// payload d'échange `PrinterSettingsPayload`.
///
/// On partage la CONFIG (modèle, papier, coupe, qualité, réglages thermiques) — JAMAIS l'appairage
/// Bluetooth ni l'identité d'une imprimante précise (UUID BLE, IP, alias, nom), propres à chaque
/// appareil. À l'import, on applique les réglages SANS toucher à la connexion courante.
@MainActor
enum PrinterSettingsSharing {

    /// Capture l'état courant des réglages dans un payload partageable.
    /// La préférence d'interface Brother (ble/wifi) est une préférence utilisateur (pas une adresse)
    /// → on la lit dans UserDefaults comme l'écran de réglages.
    static func capture(setup: PrinterSetup, printer: PrinterManager) -> PrinterSettingsPayload {
        let brotherConnection = UserDefaults.standard.string(forKey: "brother.connection")
            .flatMap(BrotherConnection.init)
        return PrinterSettingsPayload(
            brand: setup.brand,
            brotherModel: setup.brotherModel,
            brotherMedia: setup.brotherMedia,
            brotherCut: setup.cut,
            brotherQuality: setup.quality,
            brotherConnection: brotherConnection,
            copies: setup.copies,
            netum: setup.netum,
            pocketDensityValue: printer.density.rawValue,
            pocketLeadingFeedDots: printer.leadingFeedDots,
            pocketTrailingFeedDots: printer.trailingFeedDots,
            pocketRotate180: printer.rotateContent180)
    }

    /// Applique les réglages reçus. Chaque champ absent est ignoré (on garde la valeur locale).
    /// On ne touche à AUCUN identifiant de connexion : l'imprimante appairée reste la même.
    /// `PrinterSetup` normalise lui-même papier/coupe via ses `didSet` (modèle incompatible →
    /// papier de repli, coupe restreinte), donc l'ordre modèle-puis-papier est respecté.
    static func apply(_ payload: PrinterSettingsPayload, setup: PrinterSetup, printer: PrinterManager) {
        // Marque et modèle d'abord : le modèle conditionne papier/coupe compatibles.
        if let brand = payload.brand { setup.brand = brand }
        if let model = payload.brotherModel { setup.brotherModel = model }
        if let media = payload.brotherMedia { setup.brotherMedia = media }
        if let cut = payload.brotherCut { setup.cut = cut }
        if let quality = payload.brotherQuality { setup.quality = quality }
        if let copies = payload.copies { setup.copies = min(99, max(1, copies)) }
        if let connection = payload.brotherConnection {
            UserDefaults.standard.set(connection.rawValue, forKey: "brother.connection")
        }
        if var netum = payload.netum {
            // Conserve les réglages de TRANSPORT BLE locaux (dépendent de l'appareil/liaison),
            // comme le fait déjà la restauration depuis l'historique.
            netum.writeWithResponse = setup.netum.writeWithResponse
            netum.packetDelayMS = setup.netum.packetDelayMS
            setup.netum = netum.normalized
        }
        if let d = payload.pocketDensityValue, let density = PrintDensity(rawValue: d) {
            printer.density = density
        }
        if let leading = payload.pocketLeadingFeedDots { printer.leadingFeedDots = max(0, min(leading, 80)) }
        if let trailing = payload.pocketTrailingFeedDots { printer.trailingFeedDots = trailing }
        if let rotate = payload.pocketRotate180 { printer.rotateContent180 = rotate }
    }

    /// Résumé lisible de ce qui va être partagé, pour l'écran de partage.
    static func summary(for payload: PrinterSettingsPayload) -> String {
        let brand: String
        switch payload.brand {
        case .pocket5890: brand = "Pocket 5890"
        case .brother: brand = "Brother \(payload.brotherModel?.title ?? "")"
        case .netum: brand = "NETUM NT-H861"
        case nil: brand = NSLocalizedString("Imprimante", comment: "Printer")
        }
        return String(format: NSLocalizedString("Réglages %@ (modèle, papier, qualité). L’appairage Bluetooth n’est pas partagé.", comment: "Printer share summary"), brand)
    }
}
