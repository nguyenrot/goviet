import XCTest
@testable import GoVietShellCore

final class RuntimeStateTests: XCTestCase {
    func testAppContextIsPublishedAtomically() {
        let state = RuntimeState()
        state.applyAppContext(
            bundleID: "com.example.terminal",
            processID: 73,
            strategy: .slow,
            vietnameseOn: false
        )

        let snapshot = state.processingSnapshot
        XCTAssertFalse(snapshot.shouldProcess)
        XCTAssertEqual(snapshot.strategy, .slow)
        XCTAssertEqual(snapshot.frontProcessID, 73)
    }

    func testHotkeyModeChangesBeforeMainThreadPersistence() {
        let state = RuntimeState()
        state.applyAppContext(
            bundleID: "com.example.editor",
            processID: 91,
            strategy: .fast,
            vietnameseOn: true
        )

        let change = state.toggleVietnamese()

        XCTAssertFalse(change.vietnameseOn)
        XCTAssertEqual(change.bundleID, "com.example.editor")
        XCTAssertEqual(change.processID, 91)
        XCTAssertFalse(state.processingSnapshot.shouldProcess)
    }

    func testSecureInputAlwaysDisablesProcessing() {
        let state = RuntimeState()
        state.applyAppContext(
            bundleID: "com.example.login",
            processID: 101,
            strategy: .fast,
            vietnameseOn: true
        )

        state.secureInput = true

        XCTAssertFalse(state.processingSnapshot.shouldProcess)
    }

    func testPassthroughProfileAlwaysDisablesProcessing() {
        let state = RuntimeState()
        state.applyAppContext(
            bundleID: "com.example.game",
            processID: 102,
            strategy: .passthrough,
            vietnameseOn: true
        )

        XCTAssertFalse(state.processingSnapshot.shouldProcess)
    }
}
