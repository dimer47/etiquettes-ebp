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
                .full(TemplateCell(content: .dateGeneration, style: CellStyle(alignH: .center, size: .s)))
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
        XCTAssertEqual(restored.lines[4].cells[0].content, .dateGeneration)
    }

    func testCellContentCodableAllKinds() throws {
        let kinds: [CellContent] = [.vide, .designation, .refArticle, .refRayon, .famille,
                                    .prixTTC, .codeBarres, .dateGeneration, .texteLibre("x")]
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
        let dateText = CellContent.dateGeneration.text(for: label, formattedPrice: nil)
        XCTAssertEqual(dateText, LabelDateFormatter.text(for: date))
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

    func testDateIsOptionalAndBackwardCompatible() throws {
        // Une étiquette sauvegardée sans date (ancien format) décode avec generatedAt nil.
        let legacy = #"{"name":"X","category":"C","shelfReference":"R","productReference":"P","ean":"4006381333931","price":"1,00"}"#
        let label = try JSONDecoder().decode(ProductLabel.self, from: Data(legacy.utf8))
        XCTAssertNil(label.generatedAt)
        XCTAssertNil(label.generatedAtText)
        XCTAssertNil(CellContent.dateGeneration.text(for: label, formattedPrice: nil))
    }
}
