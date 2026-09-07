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

    func testOrdinaryKeysShareDeliveryWithPacedReplacements() {
        for strategy in [InjectionStrategy.slow, .selectAndRetype] {
            XCTAssertTrue(EventRouting.shouldSerializeKey(
                isKeyboardEvent: true, hasSystemModifiers: false,
                shouldProcess: true, strategy: strategy,
                expectedProcessID: 42, eventProcessID: 42
            ))
        }
    }

    func testSystemEventsAndUnprocessedAppsKeepNormalRouting() {
        let cases: [(Bool, Bool, Bool, InjectionStrategy, pid_t?)] = [
            (false, false, true, .slow, 42), // pointer/modifier event
            (true, true, true, .slow, 42), // system shortcut
            (true, false, false, .slow, 42), // EN / secure input
            (true, false, true, .passthrough, 42), // excluded app
            (true, false, true, .fast, 42), // synchronous tap delivery
            (true, false, true, .slow, 43), // stale app context
            (true, false, true, .slow, nil), // unknown event target
        ]
        for (keyboard, modifiers, process, strategy, target) in cases {
            XCTAssertFalse(EventRouting.shouldSerializeKey(
                isKeyboardEvent: keyboard, hasSystemModifiers: modifiers,
                shouldProcess: process, strategy: strategy,
                expectedProcessID: 42, eventProcessID: target
            ))
        }
    }
}
