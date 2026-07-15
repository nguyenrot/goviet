import CoreGraphics
import Foundation

/// Marker stamped on every event GõViệt synthesizes so the tap callback can
/// ignore its own events ("GVIT").
let kGoVietEventMarker: Int64 = 0x4756_4954

private final class SendableEvent: @unchecked Sendable {
    let event: CGEvent

    init(_ event: CGEvent) {
        self.event = event
    }
}

private final class InjectionRequest: @unchecked Sendable {
    let backspaces: Int
    let text: [UInt16]
    let strategy: InjectionStrategy
    let slowDelayUS: UInt32
    let originalEvent: SendableEvent?

    init(
        backspaces: Int,
        text: [UInt16],
        strategy: InjectionStrategy,
        slowDelayUS: UInt32,
        originalEvent: CGEvent?
    ) {
        self.backspaces = backspaces
        self.text = text
        self.strategy = strategy
        self.slowDelayUS = slowDelayUS
        if let originalEvent, let copy = originalEvent.copy() {
            copy.setIntegerValueField(.eventSourceUserData, value: kGoVietEventMarker)
            self.originalEvent = SendableEvent(copy)
        } else {
            self.originalEvent = nil
        }
    }
}

/// Serializes slow injection outside the event-tap callback. `pending` is
/// incremented before the callback returns, so later physical events can be
/// consumed and replayed behind the replacement that logically precedes them.
private final class InjectionScheduler: @unchecked Sendable {
    static let shared = InjectionScheduler()

    private let queue = DispatchQueue(label: "com.kynguyen.goviet.inject", qos: .userInteractive)
    private let lock = NSLock()
    private var pending = 0

    var hasPending: Bool {
        lock.withLock { pending > 0 }
    }

    /// Schedule when forced (the slow strategy) or when another injection is
    /// already queued. Returns false when the caller should execute inline.
    func schedule(
        force: Bool,
        operation: @escaping @Sendable () -> Void
    ) -> Bool {
        let accepted = lock.withLock {
            guard force || pending > 0 else { return false }
            pending += 1
            return true
        }
        guard accepted else { return false }

        queue.async {
            operation()
            self.lock.withLock {
                self.pending -= 1
            }
        }
        return true
    }
}

/// Posts synthetic edits into the event stream. Fast paths stay at the tap
/// point; slow paths run on a serial queue while EventTapManager defers later
/// physical input behind them, preserving event order without timing out the
/// tap callback.
enum TextInjector {
    private static let scheduler = InjectionScheduler.shared
    private static let kVKReturn: CGKeyCode = 36
    private static let kVKTab: CGKeyCode = 48
    private static let kVKDelete: CGKeyCode = 51
    private static let kVKLeftArrow: CGKeyCode = 123

    /// Max UTF-16 units per synthesized text event; chunks never split a
    /// Character, so a single extended grapheme may exceed this soft limit.
    private static let chunkSize = 20
    private static let slowBulkChunkSize = 64
    private static let slowPerCharacterLimit = 2_048
    private static let maxSlowPacingUS: UInt64 = 2_000_000

    static func inject(
        backspaces: Int,
        text: [UInt16],
        strategy: InjectionStrategy,
        slowDelayUS: UInt32,
        proxy: CGEventTapProxy?,
        originalEvent: CGEvent?
    ) {
        guard strategy != .passthrough else { return }
        let request = InjectionRequest(
            backspaces: backspaces,
            text: text,
            strategy: strategy,
            slowDelayUS: slowDelayUS,
            originalEvent: originalEvent
        )

        if scheduler.schedule(force: strategy == .slow, operation: {
            perform(request, proxy: nil, postGlobally: true)
        }) {
            return
        }
        perform(request, proxy: proxy, postGlobally: false)
    }

    /// If slow injection is pending, consume and replay this physical event on
    /// the same serial queue. The marker prevents it from entering the engine
    /// a second time; its first pass already updated engine state.
    static func deferEventIfNeeded(_ event: CGEvent) -> Bool {
        guard scheduler.hasPending else { return false }
        guard let copy = event.copy() else { return false }
        copy.setIntegerValueField(.eventSourceUserData, value: kGoVietEventMarker)
        let boxed = SendableEvent(copy)
        return scheduler.schedule(force: false) {
            boxed.event.post(tap: .cgSessionEventTap)
        }
    }

    private static func perform(
        _ request: InjectionRequest,
        proxy: CGEventTapProxy?,
        postGlobally: Bool
    ) {
        let source = CGEventSource(stateID: .privateState)
        switch request.strategy {
        case .fast:
            deleteByBackspace(
                request.backspaces,
                source: source,
                proxy: proxy,
                postGlobally: postGlobally,
                delayUS: 0
            )
            postText(
                request.text,
                source: source,
                proxy: proxy,
                postGlobally: postGlobally,
                perCharacter: false,
                maxChunkSize: chunkSize,
                delayUS: 0
            )
        case .slow:
            let decodedText = String(decoding: request.text, as: UTF16.self)
            let perCharacter = decodedText.count <= slowPerCharacterLimit
            let maxChunkSize = perCharacter ? chunkSize : slowBulkChunkSize
            let textSteps = slowTextEventCount(
                decodedText,
                perCharacter: perCharacter,
                maxChunkSize: maxChunkSize
            )
            let totalSteps = request.backspaces.addingReportingOverflow(textSteps)
            let delayUS = boundedSlowDelay(
                configuredUS: request.slowDelayUS,
                steps: totalSteps.overflow ? Int.max : totalSteps.partialValue
            )
            deleteByBackspace(
                request.backspaces,
                source: source,
                proxy: proxy,
                postGlobally: postGlobally,
                delayUS: delayUS
            )
            postText(
                request.text,
                source: source,
                proxy: proxy,
                postGlobally: postGlobally,
                perCharacter: perCharacter,
                maxChunkSize: maxChunkSize,
                delayUS: delayUS
            )
        case .selectAndRetype:
            selectLeft(
                request.backspaces,
                source: source,
                proxy: proxy,
                postGlobally: postGlobally
            )
            postText(
                request.text,
                source: source,
                proxy: proxy,
                postGlobally: postGlobally,
                perCharacter: false,
                maxChunkSize: chunkSize,
                delayUS: 0
            )
        case .passthrough:
            return
        }
        if let original = request.originalEvent?.event {
            post(original, proxy: proxy, globally: postGlobally)
        }
    }

    private static func deleteByBackspace(
        _ count: Int,
        source: CGEventSource?,
        proxy: CGEventTapProxy?,
        postGlobally: Bool,
        delayUS: UInt32
    ) {
        guard count > 0 else { return }
        for _ in 0..<count {
            postKey(
                kVKDelete,
                source: source,
                proxy: proxy,
                postGlobally: postGlobally
            )
            delay(delayUS)
        }
    }

    private static func selectLeft(
        _ count: Int,
        source: CGEventSource?,
        proxy: CGEventTapProxy?,
        postGlobally: Bool
    ) {
        guard count > 0 else { return }
        for _ in 0..<count {
            postKey(
                kVKLeftArrow,
                source: source,
                proxy: proxy,
                postGlobally: postGlobally,
                flags: .maskShift
            )
        }
    }

    private static func postText(
        _ units: [UInt16],
        source: CGEventSource?,
        proxy: CGEventTapProxy?,
        postGlobally: Bool,
        perCharacter: Bool,
        maxChunkSize: Int,
        delayUS: UInt32
    ) {
        guard !units.isEmpty else { return }
        let text = String(decoding: units, as: UTF16.self)
        var chunk: [UInt16] = []

        func flush() {
            guard !chunk.isEmpty else { return }
            postTextEvent(
                chunk,
                source: source,
                proxy: proxy,
                postGlobally: postGlobally
            )
            delay(delayUS)
            chunk.removeAll(keepingCapacity: true)
        }

        for character in text {
            if character == "\n" || character == "\r" || character == "\r\n" {
                flush()
                postKey(
                    kVKReturn,
                    source: source,
                    proxy: proxy,
                    postGlobally: postGlobally
                )
                delay(delayUS)
                continue
            }
            if character == "\t" {
                flush()
                postKey(
                    kVKTab,
                    source: source,
                    proxy: proxy,
                    postGlobally: postGlobally
                )
                delay(delayUS)
                continue
            }

            let characterUnits = Array(String(character).utf16)
            if perCharacter {
                flush()
                postTextEvent(
                    characterUnits,
                    source: source,
                    proxy: proxy,
                    postGlobally: postGlobally
                )
                delay(delayUS)
            } else {
                if !chunk.isEmpty, chunk.count + characterUnits.count > maxChunkSize {
                    flush()
                }
                chunk.append(contentsOf: characterUnits)
            }
        }
        flush()
    }

    private static func postTextEvent(
        _ units: [UInt16],
        source: CGEventSource?,
        proxy: CGEventTapProxy?,
        postGlobally: Bool
    ) {
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
        else { return }
        var mutableUnits = units
        down.keyboardSetUnicodeString(
            stringLength: mutableUnits.count,
            unicodeString: &mutableUnits
        )
        up.keyboardSetUnicodeString(
            stringLength: mutableUnits.count,
            unicodeString: &mutableUnits
        )
        stamp(down)
        stamp(up)
        post(down, proxy: proxy, globally: postGlobally)
        post(up, proxy: proxy, globally: postGlobally)
    }

    private static func postKey(
        _ keycode: CGKeyCode,
        source: CGEventSource?,
        proxy: CGEventTapProxy?,
        postGlobally: Bool,
        flags: CGEventFlags = []
    ) {
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: keycode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keycode, keyDown: false)
        else { return }
        down.flags = flags
        up.flags = flags
        stamp(down)
        stamp(up)
        post(down, proxy: proxy, globally: postGlobally)
        post(up, proxy: proxy, globally: postGlobally)
    }

    private static func stamp(_ event: CGEvent) {
        event.setIntegerValueField(.eventSourceUserData, value: kGoVietEventMarker)
    }

    private static func post(
        _ event: CGEvent,
        proxy: CGEventTapProxy?,
        globally: Bool
    ) {
        if globally {
            event.post(tap: .cgSessionEventTap)
        } else {
            event.tapPostEvent(proxy)
        }
    }

    private static func delay(_ microseconds: UInt32) {
        if microseconds > 0 {
            usleep(microseconds)
        }
    }

    private static func boundedSlowDelay(configuredUS: UInt32, steps: Int) -> UInt32 {
        guard configuredUS > 0, steps > 0 else { return 0 }
        let budgetPerStep = maxSlowPacingUS / UInt64(steps)
        return UInt32(min(UInt64(configuredUS), budgetPerStep))
    }

    private static func slowTextEventCount(
        _ text: String,
        perCharacter: Bool,
        maxChunkSize: Int
    ) -> Int {
        if perCharacter {
            return text.count
        }

        var events = 0
        var chunkUnits = 0
        for character in text {
            if character == "\n" || character == "\r" || character == "\r\n"
                || character == "\t"
            {
                if chunkUnits > 0 {
                    events += 1
                    chunkUnits = 0
                }
                events += 1
                continue
            }

            let unitCount = String(character).utf16.count
            if chunkUnits > 0, chunkUnits + unitCount > maxChunkSize {
                events += 1
                chunkUnits = 0
            }
            chunkUnits += unitCount
        }
        return events + (chunkUnits > 0 ? 1 : 0)
    }
}
