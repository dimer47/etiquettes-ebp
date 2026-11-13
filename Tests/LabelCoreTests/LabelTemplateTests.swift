import XCTest
@testable import LabelCore

final class LabelTemplateTests: XCTestCase {

    // MARK: - Codable

    func testTemplateCodableRoundTripLinesColumns() throws {
        let template = LabelTemplate(
            name: "Mon modèle",
            lines: [
                .full(TemplateCell(content: .designation, style: CellStyle(alignH: .center, size: .l, bold: true))),
                .columns(TemplateCell(content: .refRayon, style: CellStyle(alignH: .leading, size: .s)),
                         TemplateCell(content: .refArticle, style: CellStyle(alignH: .trailing, size: .s))),
                .full(TemplateCell(content: .codeBarres, style: CellStyle(size: .m))),
                .columns(TemplateCell(content: .texteLibre("Promo"), style: CellStyle(size: .m, italic: true)),
                         TemplateCell(content: .prixTTC, style: CellStyle(alignH: .trailing, size: .xl))),
                .full(TemplateCell(content: .dateGeneration(nil), style: CellStyle(alignH: .center, size: .s)))
            ])
        let data = try JSONEncoder().encode(template)
        let restored = try JSONDecoder().decode(LabelTemplate.self, from: data)
        XCTAssertEqual(restored, template)
        XCTAssertEqual(restored.lines.count, 5)
        XCTAssertEqual(restored.lines[1].layout, .twoColumns)
        XCTAssertEqual(restored.lines[1].cells.count, 2)
        // Le texte libre conserve sa valeur.
        if case .texteLibre(let v) = restored.lines[3].cells[0].content { XCTAssertEqual(v, "Promo") }
        else { XCTFail("texte libre perdu") }
        XCTAssertTrue(restored.lines[3].cells[0].style.italic)
        XCTAssertEqual(restored.lines[4].cells[0].content, .dateGeneration(nil))
    }

    func testCellContentCodableAllKinds() throws {
        let kinds: [CellContent] = [.vide, .designation, .refArticle, .refRayon, .famille,
                                    .prixTTC, .codeBarres, .dateGeneration(nil), .texteLibre("x")]
        for kind in kinds {
            let data = try JSONEncoder().encode(TemplateCell(content: kind))
            let restored = try JSONDecoder().decode(TemplateCell.self, from: data)
            XCTAssertEqual(restored.content, kind)
        }
    }

    func testLineNormalizationEnforcesCellCount() {
        // Une ligne pleine largeur ne garde qu'une cellule.
        let full = TemplateLine(layout: .full, cells: [TemplateCell(content: .designation),
                                                       TemplateCell(content: .prixTTC)])
        XCTAssertEqual(full.cells.count, 1)
        // Une ligne deux colonnes en a toujours deux, même avec une seule fournie.
        let cols = TemplateLine(layout: .twoColumns, cells: [TemplateCell(content: .designation)])
        XCTAssertEqual(cols.cells.count, 2)
        XCTAssertEqual(cols.cells[1].content, .vide)
    }

    func testToggleLayoutKeepsFirstCell() {
        let line = TemplateLine.full(TemplateCell(content: .designation, style: CellStyle(size: .l)))
        let toggled = line.toggledLayout()
        XCTAssertEqual(toggled.layout, .twoColumns)
        XCTAssertEqual(toggled.cells[0].content, .designation)
        XCTAssertEqual(toggled.cells.count, 2)
        // Et retour à pleine largeur.
        XCTAssertEqual(toggled.toggledLayout().layout, .full)
        XCTAssertEqual(toggled.toggledLayout().cells.count, 1)
    }

    // MARK: - Migration arrangement → preset

    func testEveryArrangementHasALockedPreset() {
        for arrangement in LabelArrangement.allCases {
            let preset = LabelTemplatePresets.preset(for: arrangement)
            XCTAssertTrue(preset.isLocked)
            XCTAssertEqual(preset.baseArrangement, arrangement)
            XCTAssertEqual(preset.id, LabelTemplatePresets.id(for: arrangement))
            XCTAssertFalse(preset.lines.isEmpty)
        }
        XCTAssertEqual(LabelTemplatePresets.all.count, 6)
        // Ids distincts et stables.
        let ids = Set(LabelArrangement.allCases.map { LabelTemplatePresets.id(for: $0) })
        XCTAssertEqual(ids.count, 6)
    }

    func testLibraryResolvesArrangementPresetByMigratedID() {
        let library = LabelTemplateLibrary()
        // L'app migre l'ancien labelArrangement vers l'id du preset : on doit le retrouver.
        let id = LabelTemplatePresets.id(for: .priceFirst)
        let resolved = library.templateOrDefault(id: id)
        XCTAssertEqual(resolved.baseArrangement, .priceFirst)
        XCTAssertTrue(resolved.isLocked)
    }

    func testTemplateOrDefaultFallsBackToDefaultPreset() {
        let library = LabelTemplateLibrary()
        let unknown = UUID()
        XCTAssertEqual(library.templateOrDefault(id: unknown).baseArrangement, .current)
        XCTAssertEqual(library.templateOrDefault(id: nil).id, LabelTemplatePresets.default.id)
    }

    // MARK: - Bibliothèque (duplication, édition, suppression, verrouillage)

    func testDuplicatePresetCreatesEditableCustom() {
        var library = LabelTemplateLibrary()
        let newId = library.duplicate(id: LabelTemplatePresets.id(for: .current))
        XCTAssertNotNil(newId)
        let copy = library.template(id: newId!)!
        XCTAssertFalse(copy.isLocked)
        XCTAssertNil(copy.baseArrangement)      // matérialisé en lignes concrètes
        XCTAssertFalse(copy.lines.isEmpty)
        XCTAssertEqual(library.custom.count, 1)
    }

    func testPresetsAreNeverDeletedOrEdited() {
        var library = LabelTemplateLibrary()
        let presetId = LabelTemplatePresets.id(for: .current)
        library.delete(id: presetId)
        XCTAssertEqual(library.all.count, 6)    // presets intacts
        // update sur un modèle verrouillé est ignoré.
        var locked = LabelTemplatePresets.preset(for: .current)
        locked.name = "piraté"
        library.update(locked)
        XCTAssertEqual(library.template(id: presetId)?.name, LabelArrangement.current.title)
    }

    func testCustomCRUDAndPersistence() {
        var library = LabelTemplateLibrary()
        var template = LabelTemplateLibrary.blankTemplate(named: "A")
        library.add(template)
        template.name = "A modifié"
        library.update(template)
        XCTAssertEqual(library.template(id: template.id)?.name, "A modifié")

        // Encodage/décodage ne garde que les modèles perso.
        let data = LabelTemplateStore.encode(library.all)   // presets filtrés
        XCTAssertNotNil(data)
        let decoded = LabelTemplateStore.decode(data!)
        XCTAssertEqual(decoded.count, 1)
        XCTAssertTrue(decoded.allSatisfy { !$0.isLocked })

        library.delete(id: template.id)
        XCTAssertTrue(library.custom.isEmpty)
    }

    func testDuplicateNameIsUnique() {
        var library = LabelTemplateLibrary()
        let id = LabelTemplatePresets.id(for: .current)
        let first = library.duplicate(id: id).flatMap { library.template(id: $0) }!
        let second = library.duplicate(id: id).flatMap { library.template(id: $0) }!
        XCTAssertNotEqual(first.name, second.name)
    }

    // MARK: - Contenu bindé (couvre date + texte libre tels que rendus)

    func testCellContentTextBindsFieldsIncludingDateAndFreeText() {
        let date = Date(timeIntervalSince1970: 1_778_000_000)
        let label = ProductLabel(name: "Spray", category: "Peinture", shelfReference: "RAYON 12",
                                 productReference: "4523187", ean: "4006381333931",
                                 price: "5,95", generatedAt: date)
        XCTAssertEqual(CellContent.designation.text(for: label, formattedPrice: "5,95 €"), "Spray")
        XCTAssertEqual(CellContent.famille.text(for: label, formattedPrice: nil), "Peinture")
        XCTAssertEqual(CellContent.refRayon.text(for: label, formattedPrice: nil), "RAYON 12")
        XCTAssertEqual(CellContent.refArticle.text(for: label, formattedPrice: nil), "Réf. 4523187")
        XCTAssertEqual(CellContent.prixTTC.text(for: label, formattedPrice: "5,95 €"), "5,95 €")
        XCTAssertEqual(CellContent.texteLibre("Promo").text(for: label, formattedPrice: nil), "Promo")
        // Date formatée « JJ/MM/AAAA HH:MM:SS ».
        let dateText = CellContent.dateGeneration(nil).text(for: label, formattedPrice: nil)
        XCTAssertEqual(dateText, LabelDateFormatter.text(for: date, pattern: nil))
        XCTAssertNotNil(dateText)
        XCTAssertTrue(dateText!.range(of: #"^\d{2}/\d{2}/\d{4} \d{2}:\d{2}:\d{2}$"#, options: .regularExpression) != nil)
        // Contenus graphiques / vides : pas de texte.
        XCTAssertNil(CellContent.codeBarres.text(for: label, formattedPrice: "5,95 €"))
        XCTAssertNil(CellContent.vide.text(for: label, formattedPrice: nil))
    }

    // MARK: - Tailles (gamme XXS → XL)

    func testSizeScaleHasXXSAndXSInIncreasingOrder() {
        // Ordre affiché = ordre déclaré, du plus fin au plus grand.
        XCTAssertEqual(CellStyle.Size.allCases, [.xxs, .xs, .s, .m, .l, .xl])
        XCTAssertEqual(CellStyle.Size.allCases.map(\.title), ["XXS", "XS", "S", "M", "L", "XL"])
        // bandHeight (hauteur d'une ligne, dont une ligne vide = interligne) strictement croissante.
        let bands = CellStyle.Size.allCases.map(\.bandHeight)
        XCTAssertEqual(bands, bands.sorted())
        XCTAssertEqual(Set(bands).count, bands.count)
        // XXS est l'espace le plus fin, plus petit que l'ancien plancher S.
        XCTAssertLessThan(CellStyle.Size.xxs.bandHeight, CellStyle.Size.s.bandHeight)
        XCTAssertLessThan(CellStyle.Size.xs.bandHeight, CellStyle.Size.s.bandHeight)
        // Police aussi croissante et toujours strictement positive.
        let fonts = CellStyle.Size.allCases.map(\.fontSize)
        XCTAssertEqual(fonts, fonts.sorted())
        XCTAssertTrue(fonts.allSatisfy { $0 > 0 })
    }

    func testSizeCodableRoundTripForNewCases() throws {
        for size in [CellStyle.Size.xxs, .xs] {
            let cell = TemplateCell(content: .vide, style: CellStyle(size: size))
            let restored = try JSONDecoder().decode(TemplateCell.self, from: JSONEncoder().encode(cell))
            XCTAssertEqual(restored.style.size, size)
        }
    }

    // MARK: - Format de la date de génération

    func testDatePresetAndCustomFormatRenderExpectedString() {
        let date = Date(timeIntervalSince1970: 1_778_000_000) // valeur fixe
        let label = ProductLabel(ean: "4006381333931", generatedAt: date)
        // Format par défaut (pattern nil).
        let def = CellContent.dateGeneration(nil).text(for: label, formattedPrice: nil)
        XCTAssertEqual(def, LabelDateFormatter.text(for: date, pattern: "dd/MM/yyyy HH:mm:ss"))
        // Preset « JJ/MM » → pattern "dd/MM".
        let short = CellContent.dateGeneration("dd/MM").text(for: label, formattedPrice: nil)
        XCTAssertEqual(short, LabelDateFormatter.text(for: date, pattern: "dd/MM"))
        XCTAssertTrue(short!.range(of: #"^\d{2}/\d{2}$"#, options: .regularExpression) != nil)
        // Format heure seule.
        let hm = CellContent.dateGeneration("HH:mm").text(for: label, formattedPrice: nil)
        XCTAssertTrue(hm!.range(of: #"^\d{2}:\d{2}$"#, options: .regularExpression) != nil)
    }

    func testTokensToPatternConversion() {
        XCTAssertEqual(LabelDateFormatter.pattern(fromTokens: "JJ/MM/AAAA"), "dd/MM/yyyy")
        XCTAssertEqual(LabelDateFormatter.pattern(fromTokens: "AAAA-MM-JJ HH:mm:ss"), "yyyy-MM-dd HH:mm:ss")
        XCTAssertEqual(LabelDateFormatter.pattern(fromTokens: "HH:mm"), "HH:mm")
        // Et l'aller-retour pattern → tokens → pattern est stable.
        for preset in LabelDateFormatter.presets {
            let tokens = LabelDateFormatter.tokens(fromPattern: preset.pattern)
            XCTAssertEqual(LabelDateFormatter.pattern(fromTokens: tokens), preset.pattern, "preset \(preset.label)")
        }
    }

    func testDateFormatPersistsOnCell() throws {
        let cell = TemplateCell(content: .dateGeneration("dd/MM"))
        let restored = try JSONDecoder().decode(TemplateCell.self, from: JSONEncoder().encode(cell))
        XCTAssertEqual(restored.content, .dateGeneration("dd/MM"))
        XCTAssertEqual(restored.content.dateFormatPattern, "dd/MM")
        // Une date sans format choisi décode avec pattern nil (défaut).
        let plain = TemplateCell(content: .dateGeneration(nil))
        let restoredPlain = try JSONDecoder().decode(TemplateCell.self, from: JSONEncoder().encode(plain))
        XCTAssertEqual(restoredPlain.content, .dateGeneration(nil))
        XCTAssertNil(restoredPlain.content.dateFormatPattern)
    }

    func testDateIsOptionalAndBackwardCompatible() throws {
        // Une étiquette sauvegardée sans date (ancien format) décode avec generatedAt nil.
        let legacy = #"{"name":"X","category":"C","shelfReference":"R","productReference":"P","ean":"4006381333931","price":"1,00"}"#
        let label = try JSONDecoder().decode(ProductLabel.self, from: Data(legacy.utf8))
        XCTAssertNil(label.generatedAt)
        XCTAssertNil(label.generatedAtText)
        XCTAssertNil(CellContent.dateGeneration(nil).text(for: label, formattedPrice: nil))
    }

    // MARK: - Nouveaux champs bindables

    func testNewBindableContentsResolveFromLabel() {
        let label = ProductLabel(name: "N", priceExclVat: "420,00 €", vatAmount: "84,00 €",
                                 realStock: "5", virtualStock: "8", subFamily: "SF001",
                                 supplier: "FR01066", unit: "UNIT", weight: "12,5", volume: "0,035")
        XCTAssertEqual(CellContent.prixHT.text(for: label, formattedPrice: nil), "420,00 €")
        XCTAssertEqual(CellContent.montantTVA.text(for: label, formattedPrice: nil), "84,00 €")
        XCTAssertEqual(CellContent.stockReel.text(for: label, formattedPrice: nil), "5")
        XCTAssertEqual(CellContent.stockDispo.text(for: label, formattedPrice: nil), "8")
        XCTAssertEqual(CellContent.sousFamille.text(for: label, formattedPrice: nil), "SF001")
        XCTAssertEqual(CellContent.fournisseur.text(for: label, formattedPrice: nil), "FR01066")
        XCTAssertEqual(CellContent.unite.text(for: label, formattedPrice: nil), "UNIT")
        XCTAssertEqual(CellContent.poids.text(for: label, formattedPrice: nil), "12,5")
        XCTAssertEqual(CellContent.volume.text(for: label, formattedPrice: nil), "0,035")
    }

    func testNewBindableContentsNilWhenFieldMissing() {
        let label = ProductLabel(name: "N")   // aucun champ additionnel renseigné
        XCTAssertNil(CellContent.prixHT.text(for: label, formattedPrice: nil))
        XCTAssertNil(CellContent.stockReel.text(for: label, formattedPrice: nil))
        XCTAssertNil(CellContent.poids.text(for: label, formattedPrice: nil))
    }

    func testNewContentsCodableRoundTrip() throws {
        for content in [CellContent.prixHT, .montantTVA, .stockReel, .stockDispo,
                        .sousFamille, .fournisseur, .unite, .poids, .volume] {
            let cell = TemplateCell(content: content)
            let restored = try JSONDecoder().decode(TemplateCell.self, from: JSONEncoder().encode(cell))
            XCTAssertEqual(restored.content, content)
        }
    }

    // MARK: - Préfixe / suffixe / placeholder

    func testPrefixSuffixWrapValue() {
        let label = ProductLabel(name: "N", weight: "12,5")
        let cell = TemplateCell(content: .poids, prefix: "Poids : ", suffix: " kg")
        XCTAssertEqual(cell.decoratedText(for: label, formattedPrice: nil), "Poids : 12,5 kg")
    }

    func testPlaceholderShownAloneWhenValueMissing() {
        let label = ProductLabel(name: "N")   // stock non renseigné
        let stockCell = TemplateCell(content: .stockReel, prefix: "[", suffix: "]", placeholder: "N/A")
        // Valeur absente → le repli s'affiche SEUL, sans préfixe ni suffixe.
        XCTAssertEqual(stockCell.decoratedText(for: label, formattedPrice: nil), "N/A")
        // Valeur présente → préfixe + valeur + suffixe.
        let withStock = ProductLabel(name: "N", realStock: "5")
        XCTAssertEqual(stockCell.decoratedText(for: withStock, formattedPrice: nil), "[5]")
    }

    func testNoValueNoPlaceholderYieldsNil() {
        let label = ProductLabel(name: "N")
        let cell = TemplateCell(content: .stockReel, prefix: "x", suffix: "y")
        XCTAssertNil(cell.decoratedText(for: label, formattedPrice: nil))
    }

    func testFreeTextAlsoDecorated() {
        let label = ProductLabel(name: "N")
        let cell = TemplateCell(content: .texteLibre("PROMO"), prefix: "<< ", suffix: " >>")
        XCTAssertEqual(cell.decoratedText(for: label, formattedPrice: nil), "<< PROMO >>")
    }

    func testDecorationsCodableRoundTrip() throws {
        let cell = TemplateCell(content: .poids, prefix: "P:", suffix: "kg", placeholder: "—",
                                codeRendering: .barcode)
        let restored = try JSONDecoder().decode(TemplateCell.self, from: JSONEncoder().encode(cell))
        XCTAssertEqual(restored.prefix, "P:")
        XCTAssertEqual(restored.suffix, "kg")
        XCTAssertEqual(restored.placeholder, "—")
        XCTAssertEqual(restored.codeRendering, .barcode)
    }

    func testDecorationsBackwardCompatibleDefaults() throws {
        // Une cellule sauvegardée avant l'ajout des décorations décode avec des valeurs neutres.
        let legacy = #"{"content":{"kind":"designation"}}"#
        let cell = try JSONDecoder().decode(TemplateCell.self, from: Data(legacy.utf8))
        XCTAssertEqual(cell.prefix, "")
        XCTAssertEqual(cell.suffix, "")
        XCTAssertEqual(cell.placeholder, "")
        XCTAssertEqual(cell.codeRendering, .barcode)
    }

    // MARK: - Rendu du code (QR)

    func testCodeRenderingModeAndPayload() {
        let barcodeCell = TemplateCell(content: .codeBarres, codeRendering: .barcode)
        XCTAssertFalse(barcodeCell.rendersAsQR)
        let qrCell = TemplateCell(content: .codeBarres, codeRendering: .qr)
        XCTAssertTrue(qrCell.rendersAsQR)
        // Le mode QR n'a d'effet que sur une cellule de type code.
        let textQR = TemplateCell(content: .designation, codeRendering: .qr)
        XCTAssertFalse(textQR.rendersAsQR)
    }

    func testQRGeneratesNonEmptyGrid() {
        let grid = QRCode.modules(for: "4006381333931")
        XCTAssertFalse(grid.isEmpty)
        XCTAssertEqual(grid.count, grid.first?.count)   // carré
        XCTAssertTrue(grid.contains { $0.contains(true) })  // au moins un module noir
    }

    func testQREmptyStringYieldsEmptyGrid() {
        XCTAssertTrue(QRCode.modules(for: "").isEmpty)
        XCTAssertTrue(QRCode.modules(for: "   ").isEmpty)
    }

    // MARK: - Signature de contenu / clé de miniature

    func testContentSignatureChangesWithDecorations() {
        let base = LabelTemplate(name: "T", lines: [.full(TemplateCell(content: .poids))])
        var withSuffix = base
        withSuffix.lines[0].cells[0].suffix = "kg"
        XCTAssertNotEqual(base.contentSignature, withSuffix.contentSignature)

        var withPlaceholder = base
        withPlaceholder.lines[0].cells[0].placeholder = "—"
        XCTAssertNotEqual(base.contentSignature, withPlaceholder.contentSignature)

        var asQR = LabelTemplate(name: "T", lines: [.full(TemplateCell(content: .codeBarres))])
        let asBarcode = asQR
        asQR.lines[0].cells[0].codeRendering = .qr
        XCTAssertNotEqual(asBarcode.contentSignature, asQR.contentSignature)
    }

    func testThumbnailKeyChangesWithContentAndLabel() {
        let t1 = LabelTemplate(name: "T", lines: [.full(TemplateCell(content: .poids))])
        var t2 = t1
        t2.lines[0].cells[0].suffix = "kg"   // modif sans changer le nombre de lignes
        let k1 = t1.thumbnailKey(forLabelSignature: 1, size: .standard, width: 384)
        let k2 = t2.thumbnailKey(forLabelSignature: 1, size: .standard, width: 384)
        XCTAssertNotEqual(k1, k2, "la clé doit changer dès qu'une décoration change")
        // Changement d'étiquette source → clé différente aussi.
        let k3 = t1.thumbnailKey(forLabelSignature: 2, size: .standard, width: 384)
        XCTAssertNotEqual(k1, k3)
    }
}
