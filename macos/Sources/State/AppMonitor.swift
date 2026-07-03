import AppKit

/// Tracks the frontmost app: applies per-app VN/EN memory, exclusion list
/// and injection strategy, and drops word state on every switch.
final class AppMonitor {
    static let shared = AppMonitor()

    private var observer: NSObjectProtocol?

    func start() {
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            self?.frontAppChanged(bundleID: app?.bundleIdentifier ?? "")
        }
        frontAppChanged(bundleID: NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "")
    }

    /// Re-evaluate rules for the current app (after settings changes).
    func refresh() {
        frontAppChanged(bundleID: RuntimeState.shared.frontBundleID)
    }

    private func frontAppChanged(bundleID: String) {
        let store = SettingsStore.shared
        let state = RuntimeState.shared
        state.frontBundleID = bundleID
        EngineBridge.clearAll()

        if store.settings.excludedApps.contains(bundleID) {
            state.strategy = .passthrough
        } else {
            let overrides = store.settings.strategyOverrides.compactMapValues(InjectionStrategy.init(rawValue:))
            state.strategy = AppProfiles.strategy(for: bundleID, overrides: overrides)
        }

        if store.settings.smartSwitch, let remembered = store.settings.rememberedMode[bundleID] {
            store.setVietnameseOnQuietly(remembered)
        }
        NotificationCenter.default.post(name: .goVietStateChanged, object: nil)
    }
}
