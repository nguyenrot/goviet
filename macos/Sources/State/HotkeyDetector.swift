import CoreGraphics
import Foundation

/// Modifier-chord toggle (default Ctrl+Shift): arms when exactly the chord
/// is held, fires on release — unless a real key was pressed in between.
final class HotkeyDetector: @unchecked Sendable {
    static let shared = HotkeyDetector()

    enum Chord: String, Codable, CaseIterable {
        case ctrlShift = "ctrl_shift"
        case ctrlSpaceLikeCmdShift = "cmd_shift"
        case none = "none"

        var display: String {
            switch self {
            case .ctrlShift: return "⌃⇧ (Control+Shift)"
            case .ctrlSpaceLikeCmdShift: return "⌘⇧ (Command+Shift)"
            case .none: return "Tắt"
            }
        }

        var flags: CGEventFlags {
            switch self {
            case .ctrlShift: return [.maskControl, .maskShift]
            case .ctrlSpaceLikeCmdShift: return [.maskCommand, .maskShift]
            case .none: return []
            }
        }
    }

    private let lock = NSLock()
    private var armed = false
    private var chord: Chord = .ctrlShift

    func setChord(_ c: Chord) {
        lock.withLock { chord = c }
    }

    /// Returns true when the toggle should fire (called from the tap thread).
    func handleFlagsChanged(_ flags: CGEventFlags) -> Bool {
        lock.withLock {
            guard chord != .none else { return false }
            let relevant: CGEventFlags = [.maskCommand, .maskControl, .maskShift, .maskAlternate]
            let current = flags.intersection(relevant)
            if current == chord.flags {
                armed = true
                return false
            }
            if armed && current.isEmpty {
                armed = false
                return true
            }
            if !current.isSubset(of: chord.flags) {
                armed = false
            }
            return false
        }
    }

    /// Any real keypress disarms the chord (it was a shortcut, not a toggle).
    func keyPressed() {
        lock.withLock { armed = false }
    }
}
