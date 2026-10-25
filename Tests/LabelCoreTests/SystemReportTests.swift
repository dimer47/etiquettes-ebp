import XCTest
@testable import LabelCore

final class SystemReportTests: XCTestCase {
    // Extrait d'un vrai rapport de TD-4550DNWB.
    private let sample = """
    general_info_modelname=TD-4550DNWB
    general_info_serialnumber=L2G747744
    general_info_program_version=V1.21 

    error_history_01=01(110)
    error_history_06=00(0)

    media_current_tape_width=102
    media_current_tape_kind=Die-cut
    setting_print_density=-1
    option_cutter_status=Not connected
    print_total_page_count=117
    error_count_total=5
    error_count_1=5
    error_count_2=0
    environment_tempature_current=22
    head_tempature_max=32
    head_replacement_count=0
    comm_serial_baudrate=9600bps
    unknown_key=x
    """

    func testEntriesAreGroupedByPrefix() {
        let report = SystemReport(parsing: sample)
        XCTAssertEqual(report.entries(.identity).count, 3)
        XCTAssertEqual(report.value("general_info_program_version"), "V1.21")
        XCTAssertEqual(report.entries(.media).map(\.key), ["media_current_tape_width", "media_current_tape_kind"])
        XCTAssertEqual(report.value("setting_print_density"), "-1")
        XCTAssertEqual(report.entries(.options).first?.value, "Not connected")
        XCTAssertEqual(report.entries(.environment).map(\.key),
                       ["environment_tempature_current", "head_tempature_max"])
        XCTAssertEqual(report.entries(.counters).map(\.key), ["print_total_page_count", "head_replacement_count"])
        XCTAssertEqual(report.entries(.other).map(\.key), ["unknown_key"])
    }

    func testRecordedErrorsSkipEmptySlots() {
        let report = SystemReport(parsing: sample)
        XCTAssertEqual(report.recordedErrors.map(\.key), ["error_history_01", "error_count_1"])
    }

    func testBlankAndMalformedLinesAreIgnored() {
        let report = SystemReport(parsing: "\n \nno equal sign\n=value\nkey=\n")
        XCTAssertEqual(report.entries(.other), [SystemReport.Entry(key: "key", value: "")])
    }
}
