import XCTest
@testable import LabelCore

final class NetumTests: XCTestCase {
    func testPaperWidths() {
        XCTAssertEqual(NetumPaper.mm80.printableDots, 576)
        XCTAssertEqual(NetumPaper.mm58.printableDots, 384)
        XCTAssertEqual(NetumPaper.mm80.printableMM, 72)
        XCTAssertEqual(NetumPaper.mm58.printableMM, 48)
        XCTAssertEqual(NetumPaper.mm58.layoutWidth, LabelRasterGeometry.layoutWidth)
    }

    func testCutCommandsMatchTheSDK() {
        XCTAssertEqual(NetumCommand.cut(.full, extraFeedDots: 16), [0x1D, 0x56, 0x41, 16])
        XCTAssertEqual(NetumCommand.cut(.partial, extraFeedDots: 0), [0x1D, 0x56, 0x42, 0])
        XCTAssertEqual(NetumCommand.cut(.full, extraFeedDots: 900), [0x1D, 0x56, 0x41, 255])
        XCTAssertEqual(NetumCommand.cut(.none, extraFeedDots: 300), [0x1B, 0x4A, 255, 0x1B, 0x4A, 45])
        XCTAssertEqual(NetumCommand.cut(.none, extraFeedDots: 0), [])
    }

    func testBeepAndStatusCommands() {
        XCTAssertEqual(NetumCommand.beep(count: 3, duration: 2), [0x1B, 0x42, 3, 2])
        XCTAssertEqual(NetumCommand.beep(count: 0, duration: 20), [0x1B, 0x42, 1, 9])
        XCTAssertEqual(NetumCommand.fullStatusRequest,
                       [0x10, 0x04, 1, 0x10, 0x04, 2, 0x10, 0x04, 3, 0x10, 0x04, 4])
    }

    func testRasterIsSplitIn24RowBands() throws {
        let widthBytes = 72
        let bitmap = [UInt8](repeating: 0xAA, count: widthBytes * 50)
        let out = try NetumCommand.raster(bitmap, width: 576, height: 50)
        // Bandes de 24, 24 puis 2 lignes, chacune avec son en-tête de 8 octets.
        XCTAssertEqual(out.count, bitmap.count + 3 * 8)
        XCTAssertEqual(Array(out.prefix(8)), [0x1D, 0x76, 0x30, 0x00, 72, 0, 24, 0])
        let second = 8 + 24 * widthBytes
        XCTAssertEqual(Array(out[second..<second + 8]), [0x1D, 0x76, 0x30, 0x00, 72, 0, 24, 0])
        let third = second + 8 + 24 * widthBytes
        XCTAssertEqual(Array(out[third..<third + 8]), [0x1D, 0x76, 0x30, 0x00, 72, 0, 2, 0])
        XCTAssertThrowsError(try NetumCommand.raster(bitmap, width: 576, height: 49))
    }

    func testLeftMarginShiftsPixelsExactly() throws {
        // 8 points de large, un seul point noir à gauche, décalé de 3 points.
        let placed = try NetumJob.placed([0x80, 0x01], width: 8, height: 2, leftMarginDots: 3)
        XCTAssertEqual(placed.width, 16)
        XCTAssertEqual(placed.bytes, [0x10, 0x00, 0x00, 0x20])
        let untouched = try NetumJob.placed([0xFF], width: 8, height: 1, leftMarginDots: 0)
        XCTAssertEqual(untouched.bytes, [0xFF])
        XCTAssertThrowsError(try NetumJob.placed([UInt8](repeating: 0, count: 72), width: 576, height: 1, leftMarginDots: 8))
    }

    func testJobCutsEveryCopyAndBeepsOnce() throws {
        var options = NetumOptions()
        options.copies = 2
        options.beep = true
        options.beepCount = 2
        options.trailingFeedDots = 8
        let bitmap = [UInt8](repeating: 0, count: 72 * 10)
        let bytes = try NetumJob.bytes(bitmap: bitmap, width: 576, height: 10, options: options)
        XCTAssertEqual(Array(bytes.prefix(2)), NetumCommand.initialize)
        XCTAssertEqual(occurrences(of: [0x1D, 0x56, 0x41, 8], in: bytes), 2)
        XCTAssertEqual(occurrences(of: [0x1B, 0x42, 2, 2], in: bytes), 1)
        XCTAssertEqual(Array(bytes.suffix(4)), [0x1B, 0x42, 2, 2])
    }

    func testJobRejectsAWideLabelOn58mmPaper() {
        var options = NetumOptions()
        options.paper = .mm58
        let bitmap = [UInt8](repeating: 0, count: 72)
        XCTAssertThrowsError(try NetumJob.bytes(bitmap: bitmap, width: 576, height: 1, options: options))
    }

    func testNormalizedOptionsStayInPrinterRanges() {
        var options = NetumOptions()
        options.paper = .mm80
        options.leftMarginDots = 40
        options.beepCount = 30
        options.copies = 0
        options.trailingFeedDots = -5
        let normalized = options.normalized
        XCTAssertEqual(normalized.leftMarginDots, 0, "aucune place à gauche sur un rouleau 80 mm")
        XCTAssertEqual(normalized.beepCount, 9)
        XCTAssertEqual(normalized.copies, 1)
        XCTAssertEqual(normalized.trailingFeedDots, 0)
        options.paper = .mm58
        options.leftMarginDots = 500
        XCTAssertEqual(options.normalized.leftMarginDots, 192)
    }

    func testOptionsDecodeWithMissingKeys() throws {
        let data = Data(#"{"paper":"mm58","beep":true}"#.utf8)
        let options = try JSONDecoder().decode(NetumOptions.self, from: data)
        XCTAssertEqual(options.paper, .mm58)
        XCTAssertTrue(options.beep)
        XCTAssertEqual(options.cut, .full)
        XCTAssertEqual(options.copies, 1)
        let roundTrip = try JSONDecoder().decode(NetumOptions.self, from: JSONEncoder().encode(options))
        XCTAssertEqual(roundTrip, options)
    }

    func testStatusDecoding() {
        let ready = NetumStatus(responses: [0x12, 0x12, 0x12, 0x12])
        XCTAssertEqual(ready, NetumStatus())
        XCTAssertTrue(ready?.canPrint ?? false)

        let coverAndPaper = NetumStatus(responses: [0x1A, 0x36, 0x12, 0x72])
        XCTAssertEqual(coverAndPaper?.offline, true)
        XCTAssertEqual(coverAndPaper?.coverOpen, true)
        XCTAssertEqual(coverAndPaper?.paperEnd, true)
        XCTAssertEqual(coverAndPaper?.canPrint, false)
        XCTAssertEqual(coverAndPaper?.problems.first, "Capot ouvert")

        let nearEnd = NetumStatus(responses: [0x12, 0x12, 0x12, 0x1E])
        XCTAssertEqual(nearEnd?.paperNearEnd, true)
        XCTAssertEqual(nearEnd?.canPrint, true, "papier presque fini : on imprime quand même")

        XCTAssertEqual(NetumStatus(responses: [0x12, 0x12, 0x1A, 0x12])?.cutterError, true)
        XCTAssertNil(NetumStatus(responses: [0x12, 0x12, 0x12]))
        XCTAssertNil(NetumStatus(responses: [0x00, 0x12, 0x12, 0x12]))
    }

    func testStatusReaderIgnoresNoiseAndWaitsForFourBytes() {
        var reader = NetumStatusReader()
        XCTAssertNil(reader.consume([0x12, 0xFF]))
        XCTAssertNil(reader.consume([0x00, 0x12]))
        let status = reader.consume([0x12, 0x1E])
        XCTAssertEqual(status?.paperNearEnd, true)
        XCTAssertNil(reader.consume([0x12]))
    }

    func testPrinterNameDetection() {
        XCTAssertTrue(NetumBLE.looksLikePrinter(name: "BLE", advertisedServices: ["18f0"]))
        XCTAssertTrue(NetumBLE.looksLikePrinter(name: "NETUM-H861", advertisedServices: []))
        XCTAssertFalse(NetumBLE.looksLikePrinter(name: "AirPods", advertisedServices: ["180A"]))
    }

    func testHistoryKeepsNetumOptionsAndReadsOldEntries() throws {
        var options = NetumOptions()
        options.cut = .partial
        let entry = PrintedLabel(label: ProductLabel(), size: .standard, arrangement: .current, densityValue: 1,
                                 leadingFeedDots: 0, trailingFeedDots: 104, rotateContent180: false, netum: options)
        let decoded = try JSONDecoder().decode(PrintedLabel.self, from: JSONEncoder().encode(entry))
        XCTAssertEqual(decoded.netum?.cut, .partial)
        // Entrée enregistrée avant la NETUM : pas de champ `netum`.
        var old = try JSONSerialization.jsonObject(with: JSONEncoder().encode(entry)) as! [String: Any]
        old.removeValue(forKey: "netum")
        let legacy = try JSONDecoder().decode(PrintedLabel.self, from: JSONSerialization.data(withJSONObject: old))
        XCTAssertNil(legacy.netum)
    }

    // MARK: - Mises en page 80 mm

    func testWideLayoutsStayInsideTheLabel() {
        for size in LabelSize.allCases {
            for arrangement in LabelArrangement.allCases {
                let layout = WideLabelLayout.layout(size: size, arrangement: arrangement)
                let context = "\(size) \(arrangement)"
                XCTAssertEqual(layout.height, size.heightDots, context)
                XCTAssertEqual(Set(layout.boxes.map(\.field)), Set(WideLabelLayout.Field.allCases), context)
                for box in layout.boxes {
                    XCTAssertGreaterThanOrEqual(box.x, 0, context)
                    XCTAssertLessThanOrEqual(box.x + box.width, WideLabelLayout.width, context)
                    XCTAssertGreaterThanOrEqual(box.y, 0, context)
                    XCTAssertLessThanOrEqual(box.y + box.height, size.heightDots, "\(context) \(box.field)")
                    XCTAssertGreaterThan(box.height, 0, context)
                }
                let block = layout.barcodeBlock
                XCTAssertGreaterThanOrEqual(block.x.lowerBound, 0, context)
                XCTAssertLessThanOrEqual(block.x.upperBound, WideLabelLayout.width, context)
            }
        }
    }

    func testWideTextNeverCoversTheBarcode() {
        let digits: Set<WideLabelLayout.Field> = [.eanFirstDigit, .eanLeftDigits, .eanRightDigits]
        for size in LabelSize.allCases {
            for arrangement in LabelArrangement.allCases {
                let layout = WideLabelLayout.layout(size: size, arrangement: arrangement)
                let block = layout.barcodeBlock
                for box in layout.boxes {
                    if digits.contains(box.field) {
                        XCTAssertGreaterThanOrEqual(box.y, block.y.upperBound, "\(size) \(arrangement)")
                        continue
                    }
                    let overlapsX = box.x < block.x.upperBound && block.x.lowerBound < box.x + box.width
                    let overlapsY = box.y < block.y.upperBound && block.y.lowerBound < box.y + box.height
                    XCTAssertFalse(overlapsX && overlapsY, "\(size) \(arrangement) \(box.field)")
                }
            }
        }
    }

    func testWideTextBoxesDoNotOverlapEachOther() {
        for size in LabelSize.allCases {
            for arrangement in LabelArrangement.allCases {
                let boxes = WideLabelLayout.layout(size: size, arrangement: arrangement).boxes
                for (i, a) in boxes.enumerated() {
                    for b in boxes[(i + 1)...] {
                        let overlap = a.x < b.x + b.width && b.x < a.x + a.width
                            && a.y < b.y + b.height && b.y < a.y + a.height
                        XCTAssertFalse(overlap, "\(size) \(arrangement) \(a.field) / \(b.field)")
                    }
                }
            }
        }
    }

    private func occurrences(of needle: [UInt8], in haystack: [UInt8]) -> Int {
        guard needle.count <= haystack.count else { return 0 }
        return (0...(haystack.count - needle.count)).filter { Array(haystack[$0..<$0 + needle.count]) == needle }.count
    }
}
