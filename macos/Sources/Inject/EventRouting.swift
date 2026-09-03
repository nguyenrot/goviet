import Darwin
import Foundation

/// Pure routing rules shared by the event tap and the asynchronous injector.
/// A missing process id is deliberately treated as "unknown" rather than a
/// mismatch because some system-owned events do not carry an application pid.
enum EventRouting {
    static func processID(rawValue: Int64) -> pid_t? {
        guard rawValue > 0, rawValue <= Int64(pid_t.max) else { return nil }
        return pid_t(rawValue)
    }

    static func isSameProcess(expected: pid_t?, actual: pid_t?) -> Bool {
        guard let expected, let actual else { return true }
        return expected == actual
    }
}
