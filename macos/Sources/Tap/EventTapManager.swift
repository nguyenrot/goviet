import AppKit
import os.log

private let log = Logger(subsystem: "com.kynguyen.goviet", category: "tap")

/// Owns the CGEventTap: creation, callback, self-healing.
/// "A non-nil tap is not a healthy tap" — re-enable on tapDisabledBy* AND
/// poll tapIsEnabled from a watchdog, because the disable event can be lost.
final class EventTapManager {
    private let tapLock = NSLock()
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var thread: Thread?
    private var watchdog: Timer?

    var onToggleHotkey: ((RuntimeModeChange) -> Void)?

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
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)
            | (1 << CGEventType.leftMouseDown.rawValue)
            | (1 << CGEventType.leftMouseUp.rawValue)
            | (1 << CGEventType.rightMouseDown.rawValue)
            | (1 << CGEventType.rightMouseUp.rawValue)
            | (1 << CGEventType.otherMouseDown.rawValue)
            | (1 << CGEventType.otherMouseUp.rawValue)
            | (1 << CGEventType.leftMouseDragged.rawValue)
            | (1 << CGEventType.rightMouseDragged.rawValue)
            | (1 << CGEventType.otherMouseDragged.rawValue)
            | (1 << CGEventType.scrollWheel.rawValue)

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
        tapLock.withLock { self.tap = tap }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        log.info("event tap started")
        CFRunLoopRun()
    }

    private func checkHealth() {
        guard let tap = tapLock.withLock({ self.tap }) else { return }
        if !CGEvent.tapIsEnabled(tap: tap) {
            log.warning("watchdog: tap found disabled — re-enabling")
            resetAfterInputDiscontinuity()
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }

    private func handle(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // Tap disabled (slow callback or user input protection) → revive.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = tapLock.withLock({ self.tap }) {
                log.warning("tap disabled (\(type.rawValue, privacy: .public)) — re-enabling")
                resetAfterInputDiscontinuity()
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
            return passOrDefer(event)

        case .leftMouseUp, .rightMouseUp, .otherMouseUp,
             .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
             .scrollWheel, .keyUp:
            return passOrDefer(event)

        case .flagsChanged:
            let verdict = HotkeyDetector.shared.handleFlagsChanged(
                event.flags,
                keycode: event.getIntegerValueField(.keyboardEventKeycode)
            )
            if verdict.fire {
                let change = RuntimeState.shared.toggleVietnamese()
                EngineBridge.clearAll()
                onToggleHotkey?(change)
            }
            return verdict.consume ? nil : passOrDefer(event)

        case .keyDown:
            return handleKeyDown(proxy: proxy, event: event)

        default:
            return passOrDefer(event)
        }
    }

    private func handleKeyDown(proxy: CGEventTapProxy, event: CGEvent) -> Unmanaged<CGEvent>? {
        HotkeyDetector.shared.keyPressed()

        let state = RuntimeState.shared.processingSnapshot
        let eventProcessID = EventRouting.processID(
            rawValue: event.getIntegerValueField(.eventTargetUnixProcessID)
        )
        guard EventRouting.isSameProcess(
            expected: state.frontProcessID,
            actual: eventProcessID
        ) else {
            // NSWorkspace activation notifications arrive on the main thread
            // and can lag the first key aimed at the new application. Never
            // apply a replacement with the previous app's strategy/state.
            log.notice(
                "target changed before app monitor expected=\(state.frontProcessID ?? 0, privacy: .public) actual=\(eventProcessID ?? 0, privacy: .public); passing key through"
            )
            EngineBridge.resetWord()
            return passOrDefer(event)
        }
        guard state.shouldProcess else {
            return passOrDefer(event)
        }

        // Held-key auto-repeat: never fight it, just drop word state.
        if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 {
            EngineBridge.resetWord()
            return passOrDefer(event)
        }

        let flags = event.flags
        let commandLike = flags.contains(.maskCommand) || flags.contains(.maskControl)
            || flags.contains(.maskAlternate) || flags.contains(.maskSecondaryFn)

        let keycode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let ch = engineScalar(from: event)

        let result = EngineBridge.processKey(keycode: keycode, char: ch, commandLike: commandLike)
        switch result.kind {
        case .passThrough:
            return passOrDefer(event)
        case let .replace(backspaces, text, forward):
            TextInjector.inject(
                backspaces: backspaces,
                text: text,
                strategy: state.strategy,
                slowDelayUS: state.slowDelayUS,
                targetProcessID: eventProcessID ?? state.frontProcessID,
                proxy: proxy,
                originalEvent: forward ? event : nil
            )
            return nil // consume the real keystroke — the injection includes it
        }
    }

    /// The Rust ABI accepts one Unicode scalar. A non-BMP scalar occupies two
    /// UTF-16 units, so decode the complete event string instead of forwarding
    /// `chars[0]` (a lone surrogate). Multi-scalar events are treated as a
    /// non-text break: the original event is still forwarded intact, while the
    /// engine safely commits and clears its current word.
    private func engineScalar(from event: CGEvent) -> UInt32 {
        var length = 0
        var units = [UniChar](repeating: 0, count: 16)
        event.keyboardGetUnicodeString(
            maxStringLength: units.count,
            actualStringLength: &length,
            unicodeString: &units
        )
        return EventTextDecoder.scalarForEngine(units: units, length: length)
    }

    /// Preserve physical input ordering while slow replacement events are
    /// paced on TextInjector's serial worker.
    private func passOrDefer(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        if TextInjector.deferEventIfNeeded(event) {
            return nil
        }
        return Unmanaged.passUnretained(event)
    }

    /// A disabled tap may have missed arbitrary physical edits. Keeping the
    /// previous word or armed hotkey would make the next replacement delete
    /// text that the engine never observed.
    private func resetAfterInputDiscontinuity() {
        EngineBridge.clearAll()
        HotkeyDetector.shared.reset()
    }
}
