import XCTest

/// Parcours de capture automatique pour fastlane snapshot.
///
/// L'app est lancée en **mode démonstration** (argument `--uitest-demo`, voir
/// `GatewaySettings`) : données factices, hors ligne, aucune gateway ni compte requis.
/// Le test navigue entre les écrans clés et appelle `snapshot(...)` à chaque étape ;
/// fastlane récupère les PNG générés pour chaque simulateur et chaque langue.
///
/// Il ne dépend d'aucune donnée réelle ni d'aucun identifiant Apple.
final class ScreenshotUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    @MainActor
    func testGenerateScreenshots() {
        let app = XCUIApplication()
        setupSnapshot(app)
        // Démarre directement sur le catalogue en mode démo (pas d'écran d'appairage).
        app.launchArguments += ["--uitest-demo"]
        app.launch()

        // 1) Catalogue des articles EBP.
        let list = app.collectionViews.firstMatch.exists ? app.collectionViews.firstMatch
                                                         : app.tables.firstMatch
        _ = list.waitForExistence(timeout: 20)
        snapshot("01-catalogue")

        // 2) Fiche article : on ouvre la première ligne de la liste.
        let firstCell = list.cells.element(boundBy: 0)
        if firstCell.waitForExistence(timeout: 10) {
            firstCell.tap()
            snapshot("02-fiche-article")

            // 3) Onglet Impression : aperçu de l'étiquette.
            let impression = app.buttons["Impression"].firstMatch
            if impression.waitForExistence(timeout: 5) {
                impression.tap()
                snapshot("03-apercu-etiquette")
            }

            // Retour à la liste.
            let back = app.navigationBars.buttons.element(boundBy: 0)
            if back.exists { back.tap() }
        }

        // 4) Réglages (bouton engrenage dans la barre d'outils du catalogue).
        //    On tente par identifiant d'accessibilité, puis repli sur l'icône système.
        let settings = app.buttons["reglages"].firstMatch.exists
            ? app.buttons["reglages"].firstMatch
            : app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'églage' OR label CONTAINS[c] 'gear'")).firstMatch
        if settings.waitForExistence(timeout: 5) {
            settings.tap()
            snapshot("04-reglages")
        }
    }
}
