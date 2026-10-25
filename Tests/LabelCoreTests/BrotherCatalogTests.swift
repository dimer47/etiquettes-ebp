import XCTest
@testable import LabelCore

final class BrotherCatalogTests: XCTestCase {
    func testCatalogMatchesTheSDKEnumeration() {
        // BRLMPrinterModel (SDK 4.13.2) : 93 modèles hors « Unknown ».
        XCTAssertEqual(BrotherModel.allCases.count, 93)
        for added in ["RJ-2031", "RJ-2131", "PT-P750Wc"] {
            XCTAssertNotNil(BrotherModel(rawValue: added), added)
        }
    }

    func testTD4550DNWBIsTheDefaultAndSupportsBLE() {
        XCTAssertEqual(BrotherModel.defaultModel, .TD_4550DNWB)
        XCTAssertEqual(BrotherModel.TD_4550DNWB.series, .td)
        XCTAssertTrue(BrotherModel.TD_4550DNWB.supportsBLE)
        XCTAssertEqual(BrotherModel.TD_4550DNWB.appConnections, [.ble, .wifi])
    }

    func testModelsWithoutBLEAreNotOfferedBLE() {
        for model in [BrotherModel.TD_4420DN, .TD_4520DN, .TD_4100N, .TD_4415D] {
            XCTAssertFalse(model.supportsBLE, model.rawValue)
            XCTAssertFalse(model.appConnections.contains(.ble), model.rawValue)
        }
        XCTAssertEqual(BrotherModel.TD_4420DN.appConnections, [.wifi])
        XCTAssertNil(BrotherModel(rawValue: "TD-4410D"))
    }

    func testBluetoothClassicIsNeverAnAppConnection() {
        for model in BrotherModel.allCases {
            XCTAssertFalse(model.appConnections.contains(.bluetoothClassic), model.rawValue)
        }
    }

    func testAdvertisedNameMatchesTheLongestModel() {
        XCTAssertEqual(BrotherModel.matching(advertisedName: "Brother TD-4550DNWB"), .TD_4550DNWB)
        XCTAssertEqual(BrotherModel.matching(advertisedName: "Brother TD-4555DNWBF"), .TD_4555DNWBF)
        XCTAssertEqual(BrotherModel.matching(advertisedName: "Brother TD-2350DFSA"), .TD_2350DFSA_203)
        XCTAssertEqual(BrotherModel.matching(advertisedName: "Brother PT-P750Wc"), .PT_P750Wc)
        XCTAssertNil(BrotherModel.matching(advertisedName: "Mini Pocket Printer_BLE"))
    }

    func testEveryModelHasACompatibleDefaultMedia() {
        for model in BrotherModel.allCases {
            XCTAssertTrue(BrotherMedia.defaultMedia(for: model).isCompatible(with: model), model.rawValue)
        }
    }

    func testDefaultMediaFollowsTheSDKSupportedList() {
        let only29 = Set([BrotherLabelSize.ql.firstIndex { $0.name == "RollW29" }!])
        let media = BrotherMedia.defaultMedia(for: .QL_820NWB, supported: only29)
        XCTAssertEqual(media, .qlLabel(only29.first!))
        XCTAssertFalse(BrotherMedia.qlLabel(22).isCompatible(with: .QL_820NWB, supported: only29))
    }

    func testPaperDependsOnThePrinter() {
        XCTAssertTrue(BrotherModel.TD_4550DNWB.paperPresets.contains(.roll(widthMM: 102)))
        XCTAssertFalse(BrotherModel.TD_2135NWB.paperPresets.contains(.roll(widthMM: 102)))
        XCTAssertTrue(BrotherModel.QL_820NWB.paperPresets.isEmpty)
        XCTAssertFalse(BrotherMedia.custom(.roll(widthMM: 102)).isCompatible(with: .TD_2135NWB))
        XCTAssertFalse(BrotherMedia.qlLabel(0).isCompatible(with: .TD_4550DNWB))
        XCTAssertFalse(BrotherMedia.sheet(.a4).isCompatible(with: .QL_820NWB))
        XCTAssertTrue(BrotherMedia.sheet(.letter).isCompatible(with: .PJ_883))
    }

    func testThreePaperKindsForTDAndRJ() {
        for model in [BrotherModel.TD_4550DNWB, .TD_2135NWB, .RJ_4250WB, .RJ_3250WB, .RJ_2150] {
            XCTAssertEqual(Set(model.paperPresets.map(\.kind)), [.roll, .dieCut, .markRoll], model.rawValue)
        }
    }

    func testPaperKindConversionKeepsPlausibleValues() {
        let roll = BrotherPaper.roll(widthMM: 102)
        let dieCut = roll.converted(to: .dieCut)
        XCTAssertEqual(dieCut.lengthMM, 102)
        XCTAssertEqual(dieCut.gapMM, 3)
        let mark = roll.converted(to: .markRoll)
        XCTAssertEqual(mark.markLengthMM, 3)
        XCTAssertLessThanOrEqual(mark.markOffsetMM, mark.lengthMM)
        XCTAssertNil(roll.printableLengthMM)
        XCTAssertEqual(BrotherPaper.dieCut(widthMM: 102, lengthMM: 51).printableLengthMM, 48)
    }

    func testSDKLabelOrderMatchesTheHeaders() {
        XCTAssertEqual(BrotherLabelSize.ql.count, 33)
        XCTAssertEqual(BrotherLabelSize.ql.first?.name, "DieCutW17H54")
        XCTAssertEqual(BrotherLabelSize.ql[22].name, "RollW62")
        XCTAssertEqual(BrotherLabelSize.ql.last?.name, "RoundW58DIA")
        XCTAssertEqual(BrotherLabelSize.pt.count, 18)
        XCTAssertEqual(BrotherLabelSize.pt[3].name, "Width12mm")
        XCTAssertEqual(BrotherLabelSize.pt.last?.name, "WidthHS_31_0mm")
    }

    func testCutterSupportPerSeries() {
        XCTAssertEqual(BrotherSeries.td.cutter, .optionalUnit)
        XCTAssertTrue(BrotherSeries.td.cutter.supportsCutAtEnd)
        XCTAssertTrue(BrotherSeries.ql.cutter.supportsCutEvery)
        XCTAssertTrue(BrotherSeries.pt.cutter.isControllable)
        XCTAssertTrue(BrotherSeries.pt.cutter.supportsCutEvery)
        XCTAssertFalse(BrotherSeries.pt.cutter.supportsCutAtEnd)
        for series in [BrotherSeries.rj, .pj, .mw] {
            XCTAssertFalse(series.cutter.isControllable, series.rawValue)
        }
    }

    func testCutOptionsAreOffByDefaultClampedAndRestricted() {
        let options = BrotherCutOptions()
        XCTAssertFalse(options.autoCut)
        XCTAssertFalse(options.cutAtEnd)
        XCTAssertFalse(options.isAnyCutRequested)
        XCTAssertEqual(BrotherCutOptions(cutEveryPages: 0).clampedCutEveryPages, 1)
        XCTAssertEqual(BrotherCutOptions(cutEveryPages: 900).clampedCutEveryPages, 255)

        let all = BrotherCutOptions(autoCut: true, cutEveryPages: 3, cutAtEnd: true)
        XCTAssertEqual(all.restricted(to: .optionalUnit), all)
        XCTAssertEqual(all.restricted(to: .autoCutOnly), BrotherCutOptions(autoCut: true, cutEveryPages: 3))
        XCTAssertEqual(all.restricted(to: .none), BrotherCutOptions())
    }

    func testMediaRoundTripsThroughCodable() throws {
        for media in [BrotherMedia.custom(.dieCut(widthMM: 102, lengthMM: 152)),
                      .custom(.markRoll(widthMM: 102, lengthMM: 152, markOffsetMM: 2, markLengthMM: 4)),
                      .qlLabel(22), .ptTape(3), .sheet(.a5), .fixedByModel] {
            let data = try JSONEncoder().encode(media)
            XCTAssertEqual(try JSONDecoder().decode(BrotherMedia.self, from: data), media)
        }
    }

    func testQualityOptionsDefaultsAndMapping() throws {
        let quality = BrotherQualityOptions()
        XCTAssertNil(quality.density)
        XCTAssertNil(quality.tdDensityRawValue)
        XCTAssertEqual(quality.halftone, .threshold)
        XCTAssertEqual(quality.clampedThreshold, 127)
        var strong = quality
        strong.density = 9
        XCTAssertEqual(strong.tdDensityRawValue, 10)
        strong.density = -1
        XCTAssertEqual(strong.tdDensityRawValue, 4)
        strong.feedMarginMM = 2
        XCTAssertEqual(strong.feedMarginDots(ydpi: 300), 24)
        // Réglages enregistrés partiellement : les autres gardent leur défaut.
        let partial = try JSONDecoder().decode(BrotherQualityOptions.self, from: Data(#"{"density":2}"#.utf8))
        XCTAssertEqual(partial.density, 2)
        XCTAssertEqual(partial.threshold, 127)
    }

    func testPrintableAreaPerMedia() {
        let roll = BrotherMedia.custom(.roll(widthMM: 102)).printableAreaMM(for: .TD_4550DNWB)
        XCTAssertEqual(roll.width, 99)
        XCTAssertNil(roll.length)
        XCTAssertEqual(BrotherMedia.fixedByModel.printableAreaMM(for: .MW_145MFi).width, 74)
        XCTAssertEqual(BrotherMedia.sheet(.a4).printableAreaMM(for: .PJ_883).length, 297)
    }
}

final class LabelRasterGeometryTests: XCTestCase {
    func testScaleOneKeepsThe5890Layout() {
        // Mêmes valeurs que LabelRenderer avant l'ajout des Brother.
        for size in LabelSize.allCases {
            let geometry = LabelRasterGeometry(layoutHeight: size.heightDots, scale: 1)
            XCTAssertEqual(geometry.width, 384)
            XCTAssertEqual(geometry.height, size.heightDots)
            XCTAssertEqual(geometry.moduleDots, 3)
            XCTAssertEqual(geometry.quietZoneDots, 30)
            XCTAssertEqual(geometry.barcodeLeft, (384 - (95 * 3 + 60)) / 2 + 30)
            XCTAssertEqual(geometry.rows(84..<154), 84..<154)
        }
    }

    func testScaledGeometryKeepsWholeModulesInsideTheWidth() {
        for scale in stride(from: 0.5, through: 8, by: 0.07) {
            let geometry = LabelRasterGeometry(layoutHeight: 240, scale: scale)
            XCTAssertEqual(geometry.width % 8, 0)
            XCTAssertGreaterThanOrEqual(geometry.moduleDots, 1)
            XCTAssertGreaterThanOrEqual(geometry.barcodeLeft, 0)
            XCTAssertLessThanOrEqual(geometry.barcodeLeft + geometry.barcodeWidth, geometry.width)
        }
    }

    func testTD4550At300DpiOnA102mmRoll() {
        // 48 mm agrandis à 99 mm imprimables, à 300 dpi.
        let area = BrotherMedia.custom(.roll(widthMM: 102)).printableAreaMM(for: .TD_4550DNWB)
        let scale = LabelRasterGeometry.scale(layoutHeight: 240, area: area, dpi: 300)
        let geometry = LabelRasterGeometry(layoutHeight: 240, scale: scale)
        XCTAssertEqual(Double(geometry.width), 99 / 25.4 * 300, accuracy: 8)
        XCTAssertEqual(geometry.moduleDots, 9)
        XCTAssertEqual(Double(geometry.height) / Double(geometry.width), 240.0 / 384.0, accuracy: 0.01)
    }

    func testDieCutLengthLimitsTheFittedSize() {
        // 102 × 51 mm : la hauteur (48 mm imprimables) limite l'étiquette.
        let fitted = LabelRasterGeometry.fittedSizeMM(layoutHeight: 240, area: (99, 48))
        XCTAssertEqual(fitted.height, 48, accuracy: 0.001)
        XCTAssertEqual(fitted.width, 76.8, accuracy: 0.001)
    }

    func testGrayscaleConversion() throws {
        // 10 × 2 : rangées alignées sur 2 octets, bit 7 = pixel de gauche.
        let bytes: [UInt8] = [0b1000_0000, 0b0100_0000, 0b0000_0001, 0b0000_0000]
        let gray = try PackedBitmap.grayscale(bytes, width: 10, height: 2)
        XCTAssertEqual(gray.count, 20)
        XCTAssertEqual(gray.indices.filter { gray[$0] == 0 }, [0, 9, 17])
        XCTAssertTrue(gray.allSatisfy { $0 == 0 || $0 == 255 })
        XCTAssertThrowsError(try PackedBitmap.grayscale(bytes, width: 16, height: 3))
    }
}
