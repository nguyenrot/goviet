import CoreGraphics
import Foundation

/// Posts synthetic edits (backspaces + replacement text) into the event
/// stream at the tap point, so ordering vs. real keystrokes is preserved.
enum TextInjector {
    private static let kVKDelete: CGKeyCode = 51
    private static let kVKLeftArrow: CGKeyCode = 123
    private static let kVKReturn: CGKeyCode = 36

    /// Max UTF-16 units per synthesized text event; large payloads confuse
    /// some apps, and 20 is the long-standing safe chunk size.
    private static let chunkSize = 20

    static func inject(
        backspaces: Int,
        text: [UInt16],
        strategy: InjectionStrategy,
        slowDelayUS: UInt32,
        proxy: CGEventTapProxy?,
        originalEvent: CGEvent?
    ) {
        let source = CGEventSource(stateID: .privateState)
        switch strategy {
        case .fast:
            deleteByBackspace(backspaces, source: source, proxy: proxy, delayUS: 0)
            postText(text, source: source, proxy: proxy, perChar: false, delayUS: 0)
        case .slow:
            deleteByBackspace(backspaces, source: source, proxy: proxy, delayUS: slowDelayUS)
            postText(text, source: source, proxy: proxy, perChar: true, delayUS: slowDelayUS)
        case .selectAndRetype:
            selectLeft(backspaces, source: source, proxy: proxy)
            postText(text, source: source, proxy: proxy, perChar: false, delayUS: 0)
        case .passthrough:
            return
        }
        if let original = originalEvent, let copy = original.copy() {
            copy.setIntegerValueField(.eventSourceUserData, value: kGoVietEventMarker)
            copy.tapPostEvent(proxy)
        }
    }

    private static func deleteByBackspace(_ n: Int, source: CGEventSource?, proxy: CGEventTapProxy?, delayUS: UInt32) {
        guard n > 0 else { return }
        for _ in 0..<n {
            postKey(kVKDelete, source: source, proxy: proxy)
            if delayUS > 0 { usleep(delayUS) }
        }
    }

    private static func selectLeft(_ n: Int, source: CGEventSource?, proxy: CGEventTapProxy?) {
        guard n > 0 else { return }
        for _ in 0..<n {
            postKey(kVKLeftArrow, source: source, proxy: proxy, flags: .maskShift)
        }
    }

    private static func postText(_ units: [UInt16], source: CGEventSource?, proxy: CGEventTapProxy?, perChar: Bool, delayUS: UInt32) {
        guard !units.isEmpty else { return }
        // Newlines/tabs inside macro expansions become real key events.
        var segment: [UInt16] = []
        func flush() {
            guard !segment.isEmpty else { return }
            let step = perChar ? 1 : chunkSize
            var i = 0
            while i < segment.count {
                let chunk = Array(segment[i..<min(i + step, segment.count)])
                postTextEvent(chunk, source: source, proxy: proxy)
                if delayUS > 0 { usleep(delayUS) }
                i += step
            }
            segment.removeAll(keepingCapacity: true)
        }
        for u in units {
            if u == 0x0A {
                flush()
                postKey(kVKReturn, source: source, proxy: proxy)
                if delayUS > 0 { usleep(delayUS) }
            } else {
                segment.append(u)
            }
        }
        flush()
    }

    private static func postTextEvent(_ units: [UInt16], source: CGEventSource?, proxy: CGEventTapProxy?) {
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
        else { return }
        var u = units
        down.keyboardSetUnicodeString(stringLength: u.count, unicodeString: &u)
        up.keyboardSetUnicodeString(stringLength: u.count, unicodeString: &u)
        down.setIntegerValueField(.eventSourceUserData, value: kGoVietEventMarker)
        up.setIntegerValueField(.eventSourceUserData, value: kGoVietEventMarker)
        down.tapPostEvent(proxy)
        up.tapPostEvent(proxy)
    }

    private static func postKey(_ vk: CGKeyCode, source: CGEventSource?, proxy: CGEventTapProxy?, flags: CGEventFlags = []) {
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: vk, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: vk, keyDown: false)
        else { return }
        down.flags = flags
        up.flags = flags
        down.setIntegerValueField(.eventSourceUserData, value: kGoVietEventMarker)
        up.setIntegerValueField(.eventSourceUserData, value: kGoVietEventMarker)
        down.tapPostEvent(proxy)
        up.tapPostEvent(proxy)
    }
}
