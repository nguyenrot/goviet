import AppKit
import SwiftUI

/// Menu-bar status item: shows VI/EN (and a lock while secure input is on),
/// hosts the quick menu and opens the Settings window.
final class MenuBarController: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?

    func start() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.font = NSFont.systemFont(ofSize: 12, weight: .bold)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        updateIcon()

        NotificationCenter.default.addObserver(
            forName: .goVietStateChanged, object: nil, queue: .main
        ) { [weak self] _ in
            self?.updateIcon()
        }
    }

    func updateIcon() {
        let state = RuntimeState.shared
        let errorSuffix = SettingsStore.shared.lastErrorMessage == nil ? "" : "!"
        let title: String
        if state.secureInput {
            title = "🔒\(errorSuffix)"
        } else if state.strategy == .passthrough || !state.vietnameseOn {
            title = "EN\(errorSuffix)"
        } else {
            title = "VI\(errorSuffix)"
        }
        statusItem.button?.title = title
    }

    // Rebuild the menu each time so checkmarks reflect current state.
    func menuNeedsUpdate(_ menu: NSMenu) {
        let store = SettingsStore.shared
        menu.removeAllItems()

        if let error = store.lastErrorMessage {
            let shortError = error.count > 100 ? "\(error.prefix(97))…" : error
            let item = NSMenuItem(
                title: "Lỗi: \(shortError)",
                action: #selector(openSettings),
                keyEquivalent: ""
            )
            item.target = self
            item.toolTip = error
            menu.addItem(item)
            menu.addItem(.separator())
        }

        let chord = HotkeyDetector.Chord(rawValue: store.settings.hotkey) ?? .ctrlShift
        let toggle = NSMenuItem(
            title: "Tiếng Việt  (\(chord.display))",
            action: #selector(toggleVietnamese), keyEquivalent: ""
        )
        toggle.target = self
        toggle.state = store.vietnameseOn ? .on : .off
        menu.addItem(toggle)

        menu.addItem(.separator())

        let methods: [(String, String)] = [("Telex", "telex"), ("VNI", "vni"), ("Simple Telex", "simple_telex")]
        for (label, value) in methods {
            let item = NSMenuItem(title: label, action: #selector(pickMethod(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = value
            item.state = store.settings.engine.method == value ? .on : .off
            menu.addItem(item)
        }

        menu.addItem(.separator())

        let front = RuntimeState.shared.frontBundleID
        if !front.isEmpty {
            let appName = NSWorkspace.shared.frontmostApplication?.localizedName ?? front
            let excluded = store.settings.excludedApps.contains(front)
            let item = NSMenuItem(
                title: excluded ? "Bật lại cho “\(appName)”" : "Tắt hẳn cho “\(appName)”",
                action: #selector(toggleExcludeFront), keyEquivalent: ""
            )
            item.target = self
            menu.addItem(item)
        }

        menu.addItem(.separator())

        let settings = NSMenuItem(title: "Cài đặt…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        let quit = NSMenuItem(title: "Thoát GõViệt", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    @objc private func toggleVietnamese() {
        SettingsStore.shared.vietnameseOn.toggle()
    }

    @objc private func pickMethod(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String else { return }
        SettingsStore.shared.settings.engine.method = value
    }

    @objc private func toggleExcludeFront() {
        let store = SettingsStore.shared
        let front = RuntimeState.shared.frontBundleID
        guard !front.isEmpty else { return }
        if let idx = store.settings.excludedApps.firstIndex(of: front) {
            store.settings.excludedApps.remove(at: idx)
        } else {
            store.settings.excludedApps.append(front)
        }
    }

    @objc func openSettings() {
        if settingsWindow == nil {
            let view = SettingsView(store: SettingsStore.shared)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 560, height: 420),
                styleMask: [.titled, .closable],
                backing: .buffered, defer: false
            )
            window.title = "GõViệt — Cài đặt"
            window.contentViewController = NSHostingController(rootView: view)
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}
