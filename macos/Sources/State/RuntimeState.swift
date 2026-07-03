import Foundation

/// Injection strategy per app — where the per-app landmines are defused.
enum InjectionStrategy: String, Codable {
    /// Backspace burst + chunked unicode text (default).
    case fast
    /// One char per event with delays (terminals).
    case slow
    /// Shift+Left selection then retype (Chromium omnibox autocomplete fix).
    case selectAndRetype
    /// Do not touch this app at all.
    case passthrough
}

/// Snapshot of everything the tap callback needs, guarded by one lock.
/// The callback runs on the tap thread; the UI mutates from the main thread.
final class RuntimeState: @unchecked Sendable {
    static let shared = RuntimeState()

    private let lock = NSLock()

    private var _vietnameseOn = true
    private var _secureInput = false
    private var _strategy: InjectionStrategy = .fast
    private var _slowDelayUS: UInt32 = 8000
    private var _frontBundleID: String = ""

    var vietnameseOn: Bool {
        get { lock.withLock { _vietnameseOn } }
        set { lock.withLock { _vietnameseOn = newValue } }
    }

    var secureInput: Bool {
        get { lock.withLock { _secureInput } }
        set { lock.withLock { _secureInput = newValue } }
    }

    var strategy: InjectionStrategy {
        get { lock.withLock { _strategy } }
        set { lock.withLock { _strategy = newValue } }
    }

    var slowDelayUS: UInt32 {
        get { lock.withLock { _slowDelayUS } }
        set { lock.withLock { _slowDelayUS = newValue } }
    }

    var frontBundleID: String {
        get { lock.withLock { _frontBundleID } }
        set { lock.withLock { _frontBundleID = newValue } }
    }

    /// Single check the tap callback makes before doing any work.
    var shouldProcess: Bool {
        lock.withLock { _vietnameseOn && !_secureInput && _strategy != .passthrough }
    }
}
