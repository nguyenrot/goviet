import XCTest
@testable import GoVietShellCore

final class EventTextDecoderTests: XCTestCase {
    func testDecodesBMPScalar() {
        XCTAssertEqual(
            EventTextDecoder.scalarForEngine(units: Array("a".utf16), length: 1),
            Unicode.Scalar("a").value
        )
    }

    func testDecodesCompleteNonBMPScalar() {
        let units = Array("😀".utf16)
        XCTAssertEqual(
            EventTextDecoder.scalarForEngine(units: units, length: units.count),
            0x1F600
        )
    }

    func testMultiScalarPayloadBecomesTextBreak() {
        let units = Array("e\u{301}".utf16)
        XCTAssertEqual(
            EventTextDecoder.scalarForEngine(units: units, length: units.count),
            0xFFFC
        )
    }

    func testOversizeAndEmptyPayloadsAreSafe() {
        XCTAssertEqual(EventTextDecoder.scalarForEngine(units: [], length: 0), 0)
        XCTAssertEqual(EventTextDecoder.scalarForEngine(units: [65], length: 2), 0xFFFC)
    }
}
