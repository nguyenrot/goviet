#if DEBUG
import CoreGraphics
import Foundation
import os.log

private let log = Logger(subsystem: "com.kynguyen.goviet", category: "selftest")

/// Dev-only end-to-end test hook: posts UNMARKED key events so they run
/// through the real tap → engine → injector pipeline into the focused app.
/// Off by default; arm with:
///   defaults write com.kynguyen.goviet SelfTestEnabled -bool true
/// then:
///   (JXA) postNotification "com.kynguyen.goviet.typetest" with the string.
/// Compiled out of Release builds: any local process could otherwise make the
/// Accessibility-trusted app type text through this hook.
enum SelfTest {
    static func register() {
        guard UserDefaults.standard.bool(forKey: "SelfTestEnabled") else {
            log.info("selftest disabled")
            return
        }
        log.info("selftest armed")
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.kynguyen.goviet.typetest"),
            object: nil, queue: nil
        ) { note in
            let s = (note.object as? String) ?? ""
            let delayUS = (note.userInfo?["delay_us"] as? NSNumber)?.uint32Value ?? 25_000
            log.info("selftest received \(s.count, privacy: .public) chars")
            guard !s.isEmpty else { return }
            DispatchQueue.global(qos: .userInitiated).async { typeString(s, delayUS: delayUS) }
        }
    }

    private static func typeString(_ s: String, delayUS: UInt32) {
        let source = CGEventSource(stateID: .privateState)
        for ch in s {
            let vk: CGKeyCode
            switch ch {
            case "⌫": vk = 51
            case "⎋": vk = 53
            case "⏎": vk = 36
            case "←": vk = 123
            case "→": vk = 124
            case "↓": vk = 125
            case "↑": vk = 126
            default: vk = ansiKeycodes[ch.lowercased()] ?? 0
            }
            guard let down = CGEvent(keyboardEventSource: source, virtualKey: vk, keyDown: true),
                  let up = CGEvent(keyboardEventSource: source, virtualKey: vk, keyDown: false)
            else { continue }
            if !["⌫", "⎋", "⏎", "←", "→", "↓", "↑"].contains(ch) {
                var units = Array(String(ch).utf16)
                down.keyboardSetUnicodeString(stringLength: units.count, unicodeString: &units)
                up.keyboardSetUnicodeString(stringLength: units.count, unicodeString: &units)
            }
            down.post(tap: .cgSessionEventTap)
            up.post(tap: .cgSessionEventTap)
            if delayUS > 0 {
                usleep(delayUS)
            }
        }
        log.info("selftest done typing")
    }

    // Match physical ANSI keys as well as their Unicode payload. Using keycode
    // zero for every character hides application behavior tied to key identity.
    private static let ansiKeycodes: [String: CGKeyCode] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6,
        "x": 7, "c": 8, "v": 9, "b": 11, "q": 12, "w": 13,
        "e": 14, "r": 15, "y": 16, "t": 17, "1": 18, "2": 19,
        "3": 20, "4": 21, "6": 22, "5": 23, "=": 24, "9": 25,
        "7": 26, "-": 27, "8": 28, "0": 29, "]": 30, "o": 31,
        "u": 32, "[": 33, "i": 34, "p": 35, "l": 37, "j": 38,
        "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43, "/": 44,
        "n": 45, "m": 46, ".": 47, "\t": 48, " ": 49, "`": 50,
    ]
}
#endif
