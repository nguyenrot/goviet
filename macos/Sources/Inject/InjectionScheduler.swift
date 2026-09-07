import Foundation

/// Serializes compatibility input outside the event-tap callback. `pending` is
/// incremented before the callback returns, so later physical events can be
/// consumed and replayed behind the replacement that logically precedes them.
final class InjectionScheduler: @unchecked Sendable {
    static let shared = InjectionScheduler()

    private let queue: DispatchQueue
    private let lock = NSLock()
    private var pending = 0

    init(
        queue: DispatchQueue = DispatchQueue(
            label: "com.kynguyen.goviet.inject",
            qos: .userInteractive
        )
    ) {
        self.queue = queue
    }

    var hasPending: Bool {
        lock.withLock { pending > 0 }
    }

    var pendingCount: Int {
        lock.withLock { pending }
    }

    /// Schedule when forced (compatibility keys/edits) or when another injection
    /// is already queued. Returns false when the caller should execute inline.
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
