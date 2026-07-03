import AppKit
import os.log

/// Marker stamped on every event GõViệt synthesizes so the tap callback can
/// ignore its own events ("GVIT").
let kGoVietEventMarker: Int64 = 0x4756_4954

private let log = Logger(subsystem: "com.kynguyen.goviet", category: "tap")

/// Owns the CGEventTap: creation, callback, self-healing.
/// "A non-nil tap is not a healthy tap" — re-enable on tapDisabledBy* AND
/// poll tapIsEnabled from a watchdog, because the disable event can be lost.
final class EventTapManager {
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var thread: Thread?
    private var watchdog: Timer?

    var onToggleHotkey: (() -> Void)?

    func start() {
        let thread = Thread { [weak self] in
            self?.threadMain()
        }
        thread.name = "goviet.tap"
        thread.qualityOfService = .userInteractive
        thread.start()
        self.thread = thread

        DispatchQueue.main.async { [weak self] in
            self?.watchdog = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
                self?.checkHealth()
            }
        }
    }

    private func threadMain() {
        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)
            | (1 << CGEventType.leftMouseDown.rawValue)
            | (1 << CGEventType.rightMouseDown.rawValue)
            | (1 << CGEventType.otherMouseDown.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { proxy, type, event, userInfo in
                let manager = Unmanaged<EventTapManager>.fromOpaque(userInfo!).takeUnretainedValue()
                return manager.handle(proxy: proxy, type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            log.error("tapCreate failed — missing Accessibility permission?")
            return
        }
        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        log.info("event tap started")
        CFRunLoopRun()
    }

    private func checkHealth() {
        guard let tap else { return }
        if !CGEvent.tapIsEnabled(tap: tap) {
            log.warning("watchdog: tap found disabled — re-enabling")
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }

    private func handle(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // Tap disabled (slow callback or user input protection) → revive.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap {
                log.warning("tap disabled (\(type.rawValue, privacy: .public)) — re-enabling")
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        // Our own synthesized events pass through untouched.
        if event.getIntegerValueField(.eventSourceUserData) == kGoVietEventMarker {
            return Unmanaged.passUnretained(event)
        }

        switch type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            EngineBridge.resetWord()
            return Unmanaged.passUnretained(event)

        case .flagsChanged:
            if HotkeyDetector.shared.handleFlagsChanged(event.flags) {
                onToggleHotkey?()
            }
            return Unmanaged.passUnretained(event)

        case .keyDown:
            return handleKeyDown(proxy: proxy, event: event)

        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private func handleKeyDown(proxy: CGEventTapProxy, event: CGEvent) -> Unmanaged<CGEvent>? {
        HotkeyDetector.shared.keyPressed()

        let state = RuntimeState.shared
        guard state.shouldProcess else {
            return Unmanaged.passUnretained(event)
        }

        // Held-key auto-repeat: never fight it, just drop word state.
        if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 {
            EngineBridge.resetWord()
            return Unmanaged.passUnretained(event)
        }

        let flags = event.flags
        let commandLike = flags.contains(.maskCommand) || flags.contains(.maskControl)
            || flags.contains(.maskAlternate) || flags.contains(.maskSecondaryFn)

        let keycode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        var length = 0
        var chars = [UniChar](repeating: 0, count: 4)
        event.keyboardGetUnicodeString(maxStringLength: 4, actualStringLength: &length, unicodeString: &chars)
        let ch: UInt32 = length > 0 ? UInt32(chars[0]) : 0

        let result = EngineBridge.processKey(keycode: keycode, char: ch, commandLike: commandLike)
        switch result.kind {
        case .passThrough:
            return Unmanaged.passUnretained(event)
        case let .replace(backspaces, text, forward):
            TextInjector.inject(
                backspaces: backspaces,
                text: text,
                strategy: state.strategy,
                slowDelayUS: state.slowDelayUS,
                proxy: proxy,
                originalEvent: forward ? event : nil
            )
            return nil // consume the real keystroke — the injection includes it
        }
    }
}
