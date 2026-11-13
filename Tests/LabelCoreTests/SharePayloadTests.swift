import XCTest
@testable import LabelCore

final class SharePayloadTests: XCTestCase {

    // MARK: - Fabriques

    private func sampleTemplate(named name: String = "Rayon promo") -> LabelTemplate {
        LabelTemplate(
            name: name,
            lines: [
                .full(TemplateCell(content: .designation, style: CellStyle(alignH: .center, size: .l))),
                .columns(TemplateCell(content: .refArticle, style: CellStyle(size: .s)),
                         TemplateCell(content: .prixTTC, style: CellStyle(alignH: .trailing, size: .xl))),
                .full(TemplateCell(content: .codeBarres, style: CellStyle(size: .m), codeRendering: .qr)),
                .full(TemplateCell(content: .texteLibre("Soldes"), style: CellStyle(italic: true),
                                   prefix: "★ ", suffix: " ★", placeholder: "—"))
            ])
    }

    // MARK: - Round-trip modèle : export → import = identique

    func testTemplateRoundTripPreservesContent() {
        let template = sampleTemplate()
        let data = TemplateSharePayload(templates: [template]).encoded()
        guard case .success(let decoded) = TemplateSharePayload.decode(data) else {
            return XCTFail("décodage échoué")
        }
        XCTAssertEqual(decoded.version, SharePayload.currentVersion)
        XCTAssertEqual(decoded.kind, .templates)
        XCTAssertEqual(decoded.templates.count, 1)
        // Contenu, style, préfixe/suffixe/placeholder et mode QR préservés à l'identique.
        XCTAssertEqual(decoded.templates[0], template)
    }

    func testTemplateRoundTripViaQRString() {
        let template = sampleTemplate()
        let data = TemplateSharePayload(templates: [template]).encoded()
        let qrString = String(data: data, encoding: .utf8)!
        guard case .success(let decoded) = TemplateSharePayload.decode(fromQRString: qrString) else {
            return XCTFail("décodage QR échoué")
        }
        XCTAssertEqual(decoded.templates[0], template)
    }

    // MARK: - Un preset verrouillé partagé devient un modèle perso éditable

    func testSharingLockedPresetUnlocksIt() {
        let preset = LabelTemplatePresets.default
        XCTAssertTrue(preset.isLocked)
        let payload = TemplateSharePayload(templates: [preset])
        XCTAssertFalse(payload.templates[0].isLocked, "un modèle partagé ne doit jamais rester verrouillé")
        // Les lignes de référence du preset sont matérialisées pour rester éditables.
        XCTAssertFalse(payload.templates[0].lines.isEmpty)
    }

    // MARK: - Bascule QR ↔ fichier selon la taille

    func testSingleTemplateExceedsQRLimitAndFallsBackToFile() {
        // Un modèle complet (~1,9 Ko) dépasse la limite SCANNABLE : il doit basculer sur fichier,
        // jamais produire un QR géant illisible. C'était la cause de l'écran de partage vide.
        let data = TemplateSharePayload(templates: [sampleTemplate()]).encoded()
        XCTAssertGreaterThan(data.count, SharePayload.qrByteLimit,
                             "un modèle complet ne doit PAS tenir dans un QR scannable → fichier")
    }

    func testManyTemplatesExceedQRLimitAndFallBackToFile() {
        // Beaucoup de modèles → le JSON dépasse la limite QR → on doit basculer sur un fichier.
        let many = (0..<40).map { sampleTemplate(named: "Modèle très détaillé numéro \($0)") }
        let data = TemplateSharePayload(templates: many).encoded()
        XCTAssertGreaterThan(data.count, SharePayload.qrByteLimit,
                             "un gros lot ne doit pas tenir dans un QR")
    }

    // MARK: - Version inconnue rejetée proprement

    func testUnsupportedVersionRejected() {
        // Un payload produit par une version future de l'app.
        let future = """
        {"version":999,"kind":"templates","templates":[]}
        """.data(using: .utf8)!
        guard case .failure(let error) = TemplateSharePayload.decode(future) else {
            return XCTFail("une version future aurait dû être rejetée")
        }
        XCTAssertEqual(error, .unsupportedVersion(999))
    }

    func testVersionZeroRejected() {
        let bad = #"{"version":0,"kind":"templates","templates":[]}"#.data(using: .utf8)!
        guard case .failure(let error) = TemplateSharePayload.decode(bad) else {
            return XCTFail("version 0 invalide aurait dû être rejetée")
        }
        XCTAssertEqual(error, .unsupportedVersion(0))
    }

    // MARK: - Données invalides

    func testNonJSONRejected() {
        let junk = "ceci n'est pas un payload".data(using: .utf8)!
        guard case .failure(let error) = TemplateSharePayload.decode(junk) else {
            return XCTFail("un contenu non-JSON aurait dû être rejeté")
        }
        XCTAssertEqual(error, .notJSON)
    }

    func testEmptyTemplatesRejected() {
        let empty = TemplateSharePayload(templates: []).encoded()
        guard case .failure(let error) = TemplateSharePayload.decode(empty) else {
            return XCTFail("un payload sans modèle aurait dû être rejeté")
        }
        XCTAssertEqual(error, .empty)
    }

    func testPrinterPayloadRejectedAsTemplate() {
        // Un fichier de réglages imprimante scanné/ouvert là où on attend un modèle.
        let printer = PrinterSettingsPayload(brand: .netum).encoded()
        guard case .failure(let error) = TemplateSharePayload.decode(printer) else {
            return XCTFail("un payload imprimante aurait dû être rejeté côté modèle")
        }
        XCTAssertEqual(error, .wrongKind)
    }

    // MARK: - Dédoublonnage à l'import

    func testImportDedupesByName() {
        var library = LabelTemplateLibrary()
        let first = library.importTemplate(sampleTemplate(named: "Promo"))
        let second = library.importTemplate(sampleTemplate(named: "Promo"))
        let third = library.importTemplate(sampleTemplate(named: "Promo"))
        XCTAssertNotEqual(first, second)
        XCTAssertNotEqual(second, third)
        let names = library.custom.map(\.name)
        XCTAssertEqual(names, ["Promo", "Promo (importé)", "Promo (importé 2)"])
    }

    func testImportDedupesAgainstPresetName() {
        var library = LabelTemplateLibrary()
        // Le nom d'un preset existe déjà parmi `all` → l'import est renommé.
        let presetName = LabelTemplatePresets.default.name
        library.importTemplate(sampleTemplate(named: presetName))
        XCTAssertEqual(library.custom.first?.name,
                       "\(presetName) (importé)")
    }

    func testImportedTemplateIsEditablePersoWithNewID() {
        var library = LabelTemplateLibrary()
        let original = sampleTemplate()
        let id = library.importTemplate(original)
        let imported = library.template(id: id)
        XCTAssertNotNil(imported)
        XCTAssertNotEqual(imported?.id, original.id, "l'import reçoit un nouvel id")
        XCTAssertEqual(imported?.isLocked, false)
        XCTAssertEqual(imported?.lines, original.lines)
    }

    func testImportTemplatesReturnsIdsInOrder() {
        var library = LabelTemplateLibrary()
        let ids = library.importTemplates([sampleTemplate(named: "A"),
                                           sampleTemplate(named: "B"),
                                           sampleTemplate(named: "A")])
        XCTAssertEqual(ids.count, 3)
        XCTAssertEqual(library.custom.map(\.name), ["A", "B", "A (importé)"])
    }

    // MARK: - Round-trip réglages imprimante

    func testPrinterSettingsRoundTrip() {
        var netum = NetumOptions()
        netum.paper = .mm58
        netum.cut = .partial
        netum.beep = true
        netum.copies = 3
        let payload = PrinterSettingsPayload(
            brand: .netum,
            brotherModel: .defaultModel,
            brotherCut: BrotherCutOptions(),
            brotherQuality: BrotherQualityOptions(),
            brotherConnection: .ble,
            copies: 2,
            netum: netum,
            pocketDensityValue: 1,
            pocketLeadingFeedDots: 8,
            pocketTrailingFeedDots: 104,
            pocketRotate180: true)
        let data = payload.encoded()
        guard case .success(let decoded) = PrinterSettingsPayload.decode(data) else {
            return XCTFail("décodage réglages échoué")
        }
        XCTAssertEqual(decoded, payload)
        XCTAssertEqual(decoded.kind, .printer)
        XCTAssertEqual(decoded.netum?.copies, 3)
        XCTAssertEqual(decoded.pocketTrailingFeedDots, 104)
    }

    func testPrinterSettingsFitsInQR() {
        let payload = PrinterSettingsPayload(brand: .netum, netum: NetumOptions(),
                                             pocketDensityValue: 1)
        XCTAssertLessThanOrEqual(payload.encoded().count, SharePayload.qrByteLimit,
                                 "des réglages imprimante doivent tenir dans un QR")
    }

    func testPrinterSettingsUnsupportedVersionRejected() {
        let future = #"{"version":999,"kind":"printer","brand":"netum"}"#.data(using: .utf8)!
        guard case .failure(let error) = PrinterSettingsPayload.decode(future) else {
            return XCTFail("version future aurait dû être rejetée")
        }
        XCTAssertEqual(error, .unsupportedVersion(999))
    }

    func testTemplatePayloadRejectedAsPrinter() {
        let templates = TemplateSharePayload(templates: [sampleTemplate()]).encoded()
        guard case .failure(let error) = PrinterSettingsPayload.decode(templates) else {
            return XCTFail("un payload modèle aurait dû être rejeté côté imprimante")
        }
        XCTAssertEqual(error, .wrongKind)
    }

    func testEmptyPrinterSettingsRejected() {
        let empty = PrinterSettingsPayload().encoded()
        guard case .failure(let error) = PrinterSettingsPayload.decode(empty) else {
            return XCTFail("des réglages vides auraient dû être rejetés")
        }
        XCTAssertEqual(error, .empty)
    }

    /// Un réglage ajouté par une version future (champ inconnu) ne fait pas échouer l'import des
    /// autres : décodage tolérant.
    func testPrinterSettingsToleratesUnknownFields() {
        let json = #"{"version":1,"kind":"printer","brand":"netum","futurReglage":42,"copies":5}"#
            .data(using: .utf8)!
        guard case .success(let decoded) = PrinterSettingsPayload.decode(json) else {
            return XCTFail("un champ inconnu ne doit pas faire échouer l'import")
        }
        XCTAssertEqual(decoded.brand, .netum)
        XCTAssertEqual(decoded.copies, 5)
    }
}
