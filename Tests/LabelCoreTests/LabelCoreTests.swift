import XCTest
@testable import LabelCore

final class LabelCoreTests: XCTestCase {
    func testPresentationSizesAndChoices() {
        XCTAssertEqual(LabelSize.allCases.map(\.heightDots), [208, 240, 312, 416])
        XCTAssertEqual(LabelSize.allCases.map(\.heightMillimeters), [26, 30, 39, 52])
        XCTAssertEqual(LabelArrangement.allCases.count, 6)
    }

    func testCategoryLibraryAvoidsEmptyAndDuplicateNames() {
        let first = CategoryLibrary.adding("  Peinture / Aérosols  ", to: [])
        XCTAssertEqual(first, ["Peinture / Aérosols"])
        XCTAssertEqual(CategoryLibrary.adding("peinture / aerosols", to: first), first)
        XCTAssertEqual(CategoryLibrary.adding(" ", to: first), first)
        XCTAssertEqual(CategoryLibrary.adding("Quincaillerie", to: first).count, 2)
    }
    func testChecksumAndCompletion() throws {
        XCTAssertEqual(try EAN13.checksum(for: "400638133393"), 1)
        XCTAssertEqual(try EAN13.completed("400638133393"), "4006381333931")
        XCTAssertThrowsError(try EAN13.completed("4006381333932"))
        XCTAssertThrowsError(try EAN13.completed("40063813339A1"))
    }

    func testPattern() throws {
        let bits = try EAN13.modules(for: "4006381333931")
        XCTAssertEqual(bits.count, 95)
        XCTAssertEqual(Array(bits.prefix(3)), [true, false, true])
        XCTAssertEqual(Array(bits[45..<50]), [false, true, false, true, false])
        XCTAssertEqual(Array(bits.suffix(3)), [true, false, true])
        XCTAssertEqual(bits.filter { $0 }.count, 45)
    }

    func testFrenchPrice() {
        let french = Locale(identifier: "fr_FR")
        XCTAssertEqual(PriceFormatter.formatted("5,95", locale: french), "5,95 €")
        XCTAssertEqual(PriceFormatter.formatted("5.95", locale: french), "5,95 €")
        XCTAssertEqual(PriceFormatter.formatted("5.95", currency: .gbp, locale: french), "5,95 £")
        XCTAssertEqual(PriceFormatter.formatted("5,95", locale: Locale(identifier: "en_US")), "5.95 €")
        XCTAssertNil(PriceFormatter.formatted("abc"))
    }

    func testOlderSavedLabelDefaultsToEuro() throws {
        let previous = #"{"name":"Spray","category":"Peinture","shelfReference":"12","productReference":"42","ean":"4006381333931","price":"5,95"}"#
        let label = try JSONDecoder().decode(ProductLabel.self, from: Data(previous.utf8))
        XCTAssertEqual(label.currency, .eur)
        XCTAssertEqual(label.priceCaption, "Prix de vente TTC")
    }

    func testPackedBitmapRotationKeepsEveryDot() throws {
        let original: [UInt8] = [0x80, 0x00, 0x20, 0x01]
        let rotated = try ThermalBitmapRotation.rotated180(original, bytesPerRow: 2, rows: 2)
        XCTAssertEqual(rotated, [0x80, 0x04, 0x00, 0x01])
        XCTAssertEqual(try ThermalBitmapRotation.rotated180(rotated, bytesPerRow: 2, rows: 2), original)
        XCTAssertThrowsError(try ThermalBitmapRotation.rotated180(original, bytesPerRow: 3, rows: 2))
    }
}
