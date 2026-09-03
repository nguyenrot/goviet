import Foundation
import Darwin

/// Injection strategy per app — where the per-app landmines are defused.
enum InjectionStrategy: String, Codable, Sendable {
    /// Backspace burst + chunked unicode text (default).
    case fast
    /// Paced events for terminals; very large payloads use bounded chunks.
    case slow
    /// Shift+Left selection then retype (Chromium omnibox autocomplete fix).
    case selectAndRetype
    /// Do not touch this app at all.
    case passthrough
}

struct RuntimeProcessingSnapshot: Sendable {
    let shouldProcess: Bool
    let strategy: InjectionStrategy
    let slowDelayUS: UInt32
    let frontProcessID: pid_t?
}

struct RuntimeModeChange: Sendable {
    let bundleID: String
    let processID: pid_t?
    let vietnameseOn: Bool
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
    private var _frontProcessID: pid_t?

    var vietnameseOn: Bool {
        get { lock.withLock { _vietnameseOn } }
        set { lock.withLock { _vietnameseOn = newValue } }
    }

    var secureInput: Bool {
        get { lock.withLock { _secureInput } }
        set { lock.withLock { _secureInput = newValue } }
    }

    var strategy: InjectionStrategy {
        lock.withLock { _strategy }
    }

    var slowDelayUS: UInt32 {
        get { lock.withLock { _slowDelayUS } }
        set { lock.withLock { _slowDelayUS = newValue } }
    }

    var frontBundleID: String {
        lock.withLock { _frontBundleID }
    }

    var frontProcessID: pid_t? {
        lock.withLock { _frontProcessID }
    }

    /// Commit an app switch as one state transition. A tap callback therefore
    /// sees either the complete old context or the complete new one.
    func applyAppContext(
        bundleID: String,
        processID: pid_t?,
        strategy: InjectionStrategy,
        vietnameseOn: Bool?
    ) {
        lock.withLock {
            _frontBundleID = bundleID
            _frontProcessID = processID
            _strategy = strategy
            if let vietnameseOn {
                _vietnameseOn = vietnameseOn
            }
        }
    }

    /// The hotkey callback runs on the tap thread. Apply its mode transition
    /// synchronously so the very next key cannot observe the old language.
    func toggleVietnamese() -> RuntimeModeChange {
        lock.withLock {
            _vietnameseOn.toggle()
            return RuntimeModeChange(
                bundleID: _frontBundleID,
                processID: _frontProcessID,
                vietnameseOn: _vietnameseOn
            )
        }
    }

    /// Read all processing decisions atomically so an app switch cannot mix
    /// `shouldProcess` from one app with the strategy of another.
    var processingSnapshot: RuntimeProcessingSnapshot {
        lock.withLock {
            RuntimeProcessingSnapshot(
                shouldProcess: _vietnameseOn && !_secureInput && _strategy != .passthrough,
                strategy: _strategy,
                slowDelayUS: _slowDelayUS,
                frontProcessID: _frontProcessID
            )
        }
    }
}
