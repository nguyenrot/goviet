import CoreGraphics
import Darwin
import Foundation
import os.log

private let injectionLog = Logger(subsystem: "com.kynguyen.goviet", category: "inject")

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
    let targetProcessID: pid_t?
    let originalEvent: SendableEvent?

    init(
        backspaces: Int,
        text: [UInt16],
        strategy: InjectionStrategy,
        slowDelayUS: UInt32,
        targetProcessID: pid_t?,
        originalEvent: CGEvent?
    ) {
        self.backspaces = backspaces
        self.text = text
        self.strategy = strategy
        self.slowDelayUS = slowDelayUS
        self.targetProcessID = targetProcessID
        if let originalEvent, let copy = originalEvent.copy() {
            copy.setIntegerValueField(.eventSourceUserData, value: kGoVietEventMarker)
            self.originalEvent = SendableEvent(copy)
        } else {
            self.originalEvent = nil
        }
    }
}

/// Fast edits stay at the tap point. Compatibility paths serialize physical
/// keys and paced replacements through the same process-targeted stream,
/// preserving event order without timing out the tap callback.
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
        targetProcessID: pid_t?,
        proxy: CGEventTapProxy?,
        originalEvent: CGEvent?
    ) {
        guard strategy != .passthrough else { return }
        let request = InjectionRequest(
            backspaces: backspaces,
            text: text,
            strategy: strategy,
            slowDelayUS: slowDelayUS,
            targetProcessID: targetProcessID,
            originalEvent: originalEvent
        )

        if scheduler.schedule(force: strategy.usesSerialDelivery, operation: {
            perform(request, proxy: nil, postGlobally: true)
        }) {
            injectionLog.debug(
                "queued strategy=\(strategy.rawValue, privacy: .public) backspaces=\(backspaces, privacy: .public) utf16=\(text.count, privacy: .public) pid=\(targetProcessID ?? 0, privacy: .public) depth=\(scheduler.pendingCount, privacy: .public)"
            )
            return
        }
        perform(request, proxy: proxy, postGlobally: false)
    }

    /// Route ordinary typing through the same queue and posting endpoint as
    /// paced replacements, even when the queue is idle. Otherwise a subsequent
    /// PID-targeted edit can overtake a letter still in the session stream.
    /// The marker prevents replayed keys from entering the engine twice.
    static func deferEventIfNeeded(_ event: CGEvent, forceSerialDelivery: Bool = false) -> Bool {
        guard forceSerialDelivery || scheduler.hasPending else { return false }
        guard let copy = event.copy() else { return false }
        copy.setIntegerValueField(.eventSourceUserData, value: kGoVietEventMarker)
        let boxed = SendableEvent(copy)
        let targetProcessID = deferredTargetProcessID(for: event)
        return scheduler.schedule(force: forceSerialDelivery) {
            if let targetProcessID {
                boxed.event.postToPid(targetProcessID)
            } else {
                boxed.event.post(tap: .cgSessionEventTap)
            }
        }
    }

    private static func perform(
        _ request: InjectionRequest,
        proxy: CGEventTapProxy?,
        postGlobally: Bool
    ) {
        let context = PostingContext(
            source: CGEventSource(stateID: .privateState),
            proxy: proxy,
            postGlobally: postGlobally,
            targetProcessID: request.targetProcessID
        )
        switch request.strategy {
        case .fast:
            deleteByBackspace(
                request.backspaces,
                context: context,
                delayUS: 0
            )
            postText(
                TextInjectionPlanner.elements(
                    for: request.text,
                    perCharacter: false,
                    maxChunkSize: chunkSize
                ),
                context: context,
                delayUS: 0
            )
        case .slow:
            let decodedText = String(decoding: request.text, as: UTF16.self)
            let perCharacter = decodedText.count <= slowPerCharacterLimit
            let maxChunkSize = perCharacter ? chunkSize : slowBulkChunkSize
            let textElements = TextInjectionPlanner.elements(
                for: request.text,
                perCharacter: perCharacter,
                maxChunkSize: maxChunkSize
            )
            let totalSteps = request.backspaces.addingReportingOverflow(textElements.count)
            let pacedSteps = totalSteps.partialValue.addingReportingOverflow(1)
            let delayUS = TextInjectionPlanner.boundedDelay(
                configuredUS: request.slowDelayUS,
                stepCount: totalSteps.overflow || pacedSteps.overflow
                    ? Int.max : pacedSteps.partialValue,
                totalBudgetUS: maxSlowPacingUS
            )
            // Give the target control time to settle before starting an edit.
            // Ordering itself comes from routing letters and edits together;
            // this compatibility interval is not a delivery barrier.
            delay(delayUS)
            deleteByBackspace(
                request.backspaces,
                context: context,
                delayUS: delayUS
            )
            postText(
                textElements,
                context: context,
                delayUS: delayUS
            )
        case .selectAndRetype:
            let elements = TextInjectionPlanner.elements(
                for: request.text,
                perCharacter: false,
                maxChunkSize: chunkSize
            )
            let delayUS = TextInjectionPlanner.boundedDelay(
                configuredUS: request.slowDelayUS,
                stepCount: request.backspaces + elements.count + 1,
                totalBudgetUS: maxSlowPacingUS
            )
            delay(delayUS)
            selectLeft(
                request.backspaces,
                context: context,
                delayUS: delayUS
            )
            postText(
                elements,
                context: context,
                delayUS: delayUS
            )
        case .passthrough:
            return
        }
        if let original = request.originalEvent?.event {
            post(original, context: context)
        }
    }

    private struct PostingContext {
        let source: CGEventSource?
        let proxy: CGEventTapProxy?
        let postGlobally: Bool
        let targetProcessID: pid_t?
    }

    private static func deleteByBackspace(
        _ count: Int,
        context: PostingContext,
        delayUS: UInt32
    ) {
        guard count > 0 else { return }
        for _ in 0..<count {
            postKey(
                kVKDelete,
                context: context
            )
            delay(delayUS)
        }
    }

    private static func selectLeft(
        _ count: Int,
        context: PostingContext,
        delayUS: UInt32
    ) {
        guard count > 0 else { return }
        for _ in 0..<count {
            postKey(
                kVKLeftArrow,
                context: context,
                flags: .maskShift
            )
            delay(delayUS)
        }
    }

    private static func postText(
        _ elements: [TextInjectionElement],
        context: PostingContext,
        delayUS: UInt32
    ) {
        for element in elements {
            switch element {
            case let .text(units):
                postTextEvent(units, context: context)
            case .returnKey:
                postKey(
                    kVKReturn,
                    context: context
                )
            case .tabKey:
                postKey(
                    kVKTab,
                    context: context
                )
            }
            delay(delayUS)
        }
    }

    private static func postTextEvent(
        _ units: [UInt16],
        context: PostingContext
    ) {
        guard let down = CGEvent(keyboardEventSource: context.source, virtualKey: 0, keyDown: true),
              let up = CGEvent(keyboardEventSource: context.source, virtualKey: 0, keyDown: false)
        else { return }
        // Unicode already encodes case. Do not inherit Shift from selection
        // events (or modifiers held on the physical keyboard) into text input.
        down.flags = []
        up.flags = []
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
        post(down, context: context)
        post(up, context: context)
    }

    private static func postKey(
        _ keycode: CGKeyCode,
        context: PostingContext,
        flags: CGEventFlags = []
    ) {
        guard let down = CGEvent(keyboardEventSource: context.source, virtualKey: keycode, keyDown: true),
              let up = CGEvent(keyboardEventSource: context.source, virtualKey: keycode, keyDown: false)
        else { return }
        down.flags = flags
        up.flags = flags
        stamp(down)
        stamp(up)
        post(down, context: context)
        post(up, context: context)
    }

    private static func stamp(_ event: CGEvent) {
        event.setIntegerValueField(.eventSourceUserData, value: kGoVietEventMarker)
    }

    private static func post(
        _ event: CGEvent,
        context: PostingContext
    ) {
        if context.postGlobally {
            if let targetProcessID = context.targetProcessID {
                event.postToPid(targetProcessID)
            } else {
                event.post(tap: .cgSessionEventTap)
            }
        } else {
            event.tapPostEvent(context.proxy)
        }
    }

    /// Plain/shift/option keyboard events are application-targeted and safe to
    /// pin to their original process. System shortcut and pointer events must
    /// re-enter the session stream so macOS can perform its normal routing.
    private static func deferredTargetProcessID(for event: CGEvent) -> pid_t? {
        guard event.type == .keyDown || event.type == .keyUp else { return nil }
        let systemModifiers: CGEventFlags = [.maskCommand, .maskControl, .maskSecondaryFn]
        guard event.flags.intersection(systemModifiers).isEmpty else { return nil }
        return EventRouting.processID(
            rawValue: event.getIntegerValueField(.eventTargetUnixProcessID)
        )
    }

    private static func delay(_ microseconds: UInt32) {
        if microseconds > 0 {
            usleep(microseconds)
        }
    }

}
