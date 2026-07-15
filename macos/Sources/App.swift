import AppKit
import ApplicationServices
import os.log

private let log = Logger(subsystem: "com.kynguyen.goviet", category: "app")

@main
enum GoVietMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let tapManager = EventTapManager()
    private let menuBar = MenuBarController()
    private var permissionTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        EngineBridge.initialize()
        SettingsStore.shared.load()
        menuBar.start()
        SecureInputMonitor.shared.start()
        AppMonitor.shared.start()
        #if DEBUG
        SelfTest.register()
        #endif

        tapManager.onToggleHotkey = {
            DispatchQueue.main.async {
                SettingsStore.shared.vietnameseOn.toggle()
            }
        }

        log.info("launched; accessibility trusted = \(AXIsProcessTrusted(), privacy: .public)")
        if AXIsProcessTrusted() {
            tapManager.start()
            log.info("accessibility already granted, tap running")
        } else {
            requestPermission()
        }
    }

    private func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        log.info("waiting for accessibility permission…")

        // Poll until the user grants it, then start the tap without relaunch.
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] timer in
            guard AXIsProcessTrusted() else { return }
            timer.invalidate()
            self?.permissionTimer = nil
            self?.tapManager.start()
            log.info("accessibility granted, tap started")
        }
    }
}
