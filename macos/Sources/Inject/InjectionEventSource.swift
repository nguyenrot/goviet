import CoreGraphics

/// Sources used for posting edits must not suppress the user's hardware input.
enum InjectionEventSource {
    static func make() -> CGEventSource? {
        guard let source = CGEventSource(stateID: .privateState) else { return nil }
        allowHardwareInput(source)
        return source
    }

    static func prepareForReplay(_ event: CGEvent) {
        guard let source = CGEventSource(event: event) else { return }
        allowHardwareInput(source)
        event.setSource(source)
    }

    private static func allowHardwareInput(_ source: CGEventSource) {
        // Quartz sources expose a 250 ms suppression interval by default.
        // A lost physical keyUp can also leave macOS PressAndHold armed.
        // Event ordering is handled by InjectionScheduler, never by dropping
        // local input. Apply this to replayed events as well as new edits.
        source.localEventsSuppressionInterval = 0
        let permitted: CGEventFilterMask = [
            .permitLocalKeyboardEvents, .permitLocalMouseEvents, .permitSystemDefinedEvents,
        ]
        source.setLocalEventsFilterDuringSuppressionState(
            permitted, state: .eventSuppressionStateSuppressionInterval
        )
        source.setLocalEventsFilterDuringSuppressionState(
            permitted, state: .eventSuppressionStateRemoteMouseDrag
        )
    }
}
