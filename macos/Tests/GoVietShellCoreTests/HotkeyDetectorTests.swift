import CoreGraphics
import XCTest
@testable import GoVietShellCore

final class HotkeyDetectorTests: XCTestCase {
    func testChordFiresOnlyOnRelease() {
        let detector = HotkeyDetector()
        detector.setChord(.ctrlShift)

        XCTAssertFalse(
            detector.handleFlagsChanged([.maskControl, .maskShift], keycode: 56).fire
        )
        XCTAssertTrue(detector.handleFlagsChanged([], keycode: 56).fire)
    }

    func testPhysicalKeyCancelsArmedChord() {
        let detector = HotkeyDetector()
        detector.setChord(.ctrlShift)
        _ = detector.handleFlagsChanged([.maskControl, .maskShift], keycode: 56)

        detector.keyPressed()

        XCTAssertFalse(detector.handleFlagsChanged([], keycode: 56).fire)
    }

    func testTapRecoveryCancelsPartiallyObservedChord() {
        let detector = HotkeyDetector()
        detector.setChord(.ctrlShift)
        _ = detector.handleFlagsChanged([.maskControl, .maskShift], keycode: 56)

        detector.reset()

        XCTAssertFalse(detector.handleFlagsChanged([], keycode: 56).fire)
    }

    func testGlobeChordIsConsumedWithoutConsumingOtherFunctionUse() {
        let detector = HotkeyDetector()
        detector.setChord(.fn)

        let globe = detector.handleFlagsChanged([.maskSecondaryFn], keycode: 0x3F)
        XCTAssertTrue(globe.consume)

        detector.reset()
        let functionArrow = detector.handleFlagsChanged([.maskSecondaryFn], keycode: 123)
        XCTAssertFalse(functionArrow.consume)
    }
}
