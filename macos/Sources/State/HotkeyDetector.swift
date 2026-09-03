import CoreGraphics
import Foundation

/// Modifier-chord toggle (default Ctrl+Shift): arms when exactly the chord
/// is held, fires on release — unless a real key was pressed in between.
final class HotkeyDetector: @unchecked Sendable {
    static let shared = HotkeyDetector()

    enum Chord: String, Codable, CaseIterable {
        case ctrlShift = "ctrl_shift"
        case ctrlSpaceLikeCmdShift = "cmd_shift"
        case fn = "fn"
        case none = "none"

        var display: String {
            switch self {
            case .ctrlShift: return "⌃⇧ (Control+Shift)"
            case .ctrlSpaceLikeCmdShift: return "⌘⇧ (Command+Shift)"
            case .fn: return "fn 🌐 (Globe)"
            case .none: return "Tắt"
            }
        }

        var flags: CGEventFlags {
            switch self {
            case .ctrlShift: return [.maskControl, .maskShift]
            case .ctrlSpaceLikeCmdShift: return [.maskCommand, .maskShift]
            case .fn: return [.maskSecondaryFn]
            case .none: return []
            }
        }
    }

    /// Keycode carried by the fn/Globe key's flagsChanged events (kVK_Function).
    private static let fnKeycode: Int64 = 0x3F

    struct FlagsVerdict {
        var fire = false
        /// Swallow the event so the system Globe action (input-source switch /
        /// emoji picker) doesn't also fire on the same keypress.
        var consume = false
    }

    private let lock = NSLock()
    private var armed = false
    private var chord: Chord = .ctrlShift

    func setChord(_ c: Chord) {
        lock.withLock { chord = c }
    }

    /// Decides whether the toggle fires and whether the event should be
    /// swallowed (called from the tap thread on every flagsChanged event).
    func handleFlagsChanged(_ flags: CGEventFlags, keycode: Int64) -> FlagsVerdict {
        lock.withLock {
            guard chord != .none else { return FlagsVerdict() }
            let consume = chord == .fn && keycode == Self.fnKeycode
            var relevant: CGEventFlags = [.maskCommand, .maskControl, .maskShift, .maskAlternate]
            if chord == .fn { relevant.insert(.maskSecondaryFn) }
            let current = flags.intersection(relevant)
            if current == chord.flags {
                armed = true
                return FlagsVerdict(fire: false, consume: consume)
            }
            if armed && current.isEmpty {
                armed = false
                return FlagsVerdict(fire: true, consume: consume)
            }
            if !current.isSubset(of: chord.flags) {
                armed = false
            }
            return FlagsVerdict(fire: false, consume: consume)
        }
    }

    /// Any real keypress disarms the chord (it was a shortcut, not a toggle).
    func keyPressed() {
        lock.withLock { armed = false }
    }

    /// Drop a partially observed chord after an event-tap discontinuity.
    func reset() {
        lock.withLock { armed = false }
    }
}
