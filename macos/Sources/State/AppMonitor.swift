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
            self?.frontAppChanged(
                bundleID: app?.bundleIdentifier ?? "",
                processID: app?.processIdentifier
            )
        }
        let app = NSWorkspace.shared.frontmostApplication
        frontAppChanged(
            bundleID: app?.bundleIdentifier ?? "",
            processID: app?.processIdentifier
        )
    }

    /// Re-evaluate rules for the current app (after settings changes).
    func refresh() {
        let state = RuntimeState.shared
        frontAppChanged(bundleID: state.frontBundleID, processID: state.frontProcessID)
    }

    private func frontAppChanged(bundleID: String, processID: pid_t?) {
        let store = SettingsStore.shared
        let state = RuntimeState.shared

        let strategy: InjectionStrategy
        if store.settings.excludedApps.contains(bundleID) {
            strategy = .passthrough
        } else {
            let overrides = store.settings.strategyOverrides.compactMapValues(InjectionStrategy.init(rawValue:))
            strategy = AppProfiles.strategy(for: bundleID, overrides: overrides)
        }

        let remembered = store.settings.smartSwitch
            ? store.settings.rememberedMode[bundleID]
            : nil
        EngineBridge.clearAll()
        state.applyAppContext(
            bundleID: bundleID,
            processID: processID,
            strategy: strategy,
            vietnameseOn: remembered
        )
        if let remembered {
            store.setVietnameseOnQuietly(remembered)
        }
        NotificationCenter.default.post(name: .goVietStateChanged, object: nil)
    }
}
