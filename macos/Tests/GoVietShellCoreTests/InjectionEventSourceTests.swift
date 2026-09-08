import CoreGraphics
import XCTest
@testable import GoVietShellCore

final class InjectionEventSourceTests: XCTestCase {
    private func assertHardwareInputAllowed(
        _ event: CGEvent,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let source = try XCTUnwrap(CGEventSource(event: event), file: file, line: line)
        XCTAssertEqual(source.localEventsSuppressionInterval, 0, file: file, line: line)
        for state in [CGEventSuppressionState.eventSuppressionStateSuppressionInterval,
                      .eventSuppressionStateRemoteMouseDrag] {
            let filter = source.getLocalEventsFilterDuringSuppressionState(state)
            XCTAssertTrue(filter.contains(.permitLocalKeyboardEvents), file: file, line: line)
            XCTAssertTrue(filter.contains(.permitLocalMouseEvents), file: file, line: line)
            XCTAssertTrue(filter.contains(.permitSystemDefinedEvents), file: file, line: line)
        }
    }

    func testReplacementEventsDoNotSuppressTheNextPhysicalKeyOrKeyUp() throws {
        let source = try XCTUnwrap(InjectionEventSource.make())
        // Unicode uses virtual key A; backspace and selection use real keycodes.
        for keycode: CGKeyCode in [0, 51, 123] {
            for down in [true, false] {
                let event = try XCTUnwrap(CGEvent(
                    keyboardEventSource: source, virtualKey: keycode, keyDown: down
                ))
                try assertHardwareInputAllowed(event)
                XCTAssertEqual(CGEventSource(event: event)?.sourceStateID, source.sourceStateID)
            }
        }
    }

    func testReplayedKeysKeepTheirPayloadAndModifiersWithoutSuppressingHardware() throws {
        for keycode: CGKeyCode in [0, 8, 9, 31, 48, 55] {
            for type in [CGEventType.keyDown, .keyUp, .flagsChanged] {
                let original = try XCTUnwrap(CGEvent(
                    keyboardEventSource: CGEventSource(stateID: .hidSystemState),
                    virtualKey: keycode, keyDown: true
                ))
                original.type = type
                original.flags = [.maskCommand, .maskShift]
                original.timestamp = 123_456
                original.setIntegerValueField(.eventTargetUnixProcessID, value: 1234)
                original.setIntegerValueField(.eventSourceUserData, value: 0x4756_4954)
                var units = Array("ó".utf16)
                original.keyboardSetUnicodeString(stringLength: units.count, unicodeString: &units)
                let copy = try XCTUnwrap(original.copy())

                InjectionEventSource.prepareForReplay(copy)

                try assertHardwareInputAllowed(copy)
                XCTAssertEqual(CGEventSource(event: copy)?.sourceStateID, .hidSystemState)
                XCTAssertEqual(copy.type, type)
                XCTAssertEqual(copy.flags, original.flags)
                XCTAssertEqual(copy.timestamp, original.timestamp)
                XCTAssertEqual(copy.getIntegerValueField(.keyboardEventKeycode), Int64(keycode))
                XCTAssertEqual(copy.getIntegerValueField(.eventTargetUnixProcessID), 1234)
                XCTAssertEqual(copy.getIntegerValueField(.eventSourceUserData), 0x4756_4954)
                var length = 0
                var actual = [UInt16](repeating: 0, count: 8)
                copy.keyboardGetUnicodeString(
                    maxStringLength: actual.count, actualStringLength: &length, unicodeString: &actual
                )
                XCTAssertEqual(Array(actual.prefix(length)), units)
            }
        }
    }
}
