import Darwin
import XCTest
@testable import GoVietShellCore

final class EventRoutingTests: XCTestCase {
    func testRejectsMissingAndOutOfRangeProcessIDs() {
        XCTAssertNil(EventRouting.processID(rawValue: 0))
        XCTAssertNil(EventRouting.processID(rawValue: -1))
        XCTAssertNil(EventRouting.processID(rawValue: Int64(pid_t.max) + 1))
    }

    func testAcceptsValidProcessID() {
        XCTAssertEqual(EventRouting.processID(rawValue: 42), 42)
    }

    func testKnownDifferentTargetsNeverShareCompositionContext() {
        XCTAssertTrue(EventRouting.isSameProcess(expected: 42, actual: 42))
        XCTAssertFalse(EventRouting.isSameProcess(expected: 42, actual: 43))
    }

    func testUnknownSystemTargetDoesNotCauseFalseMismatch() {
        XCTAssertTrue(EventRouting.isSameProcess(expected: 42, actual: nil))
        XCTAssertTrue(EventRouting.isSameProcess(expected: nil, actual: 42))
    }
}
