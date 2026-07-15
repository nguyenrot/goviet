import Carbon
import Foundation

/// Password fields turn on secure event input, which silences event taps
/// system-wide. Poll for it, bypass the engine and badge the menu icon.
final class SecureInputMonitor {
    static let shared = SecureInputMonitor()

    private var timer: Timer?

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            let secure = IsSecureEventInputEnabled()
            if RuntimeState.shared.secureInput != secure {
                EngineBridge.clearAll()
                RuntimeState.shared.secureInput = secure
                NotificationCenter.default.post(name: .goVietStateChanged, object: nil)
            }
        }
    }
}
