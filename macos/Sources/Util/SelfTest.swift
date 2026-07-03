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
/// Keep disabled outside development: any local process could make the app
/// type text through this hook.
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
            log.info("selftest received \(s.count, privacy: .public) chars")
            guard !s.isEmpty else { return }
            DispatchQueue.global(qos: .userInitiated).async { typeString(s) }
        }
    }

    private static func typeString(_ s: String) {
        let source = CGEventSource(stateID: .privateState)
        for ch in s {
            let vk: CGKeyCode
            switch ch {
            case "⌫": vk = 51
            case "⎋": vk = 53
            case "⏎": vk = 36
            default: vk = 0
            }
            guard let down = CGEvent(keyboardEventSource: source, virtualKey: vk, keyDown: true),
                  let up = CGEvent(keyboardEventSource: source, virtualKey: vk, keyDown: false)
            else { continue }
            if vk == 0 {
                var units = Array(String(ch).utf16)
                down.keyboardSetUnicodeString(stringLength: units.count, unicodeString: &units)
                up.keyboardSetUnicodeString(stringLength: units.count, unicodeString: &units)
            }
            down.post(tap: .cgSessionEventTap)
            up.post(tap: .cgSessionEventTap)
            usleep(25_000)
        }
        log.info("selftest done typing")
    }
}
