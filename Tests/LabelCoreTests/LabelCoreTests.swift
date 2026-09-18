import XCTest
@testable import LabelCore

final class LabelCoreTests: XCTestCase {
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
        XCTAssertEqual(PriceFormatter.formatted("5,95"), "5,95 €")
        XCTAssertEqual(PriceFormatter.formatted("5.95"), "5,95 €")
        XCTAssertNil(PriceFormatter.formatted("abc"))
    }
}
