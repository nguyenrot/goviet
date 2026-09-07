import Foundation

/// Default injection strategy per bundle id. User overrides in Settings win.
enum AppProfiles {
    static let defaults: [String: InjectionStrategy] = {
        var profiles: [String: InjectionStrategy] = [
            // Terminals: pace the events or characters get eaten/doubled.
            "com.apple.Terminal": .slow,
            "com.googlecode.iterm2": .slow,
            "net.kovidgoyal.kitty": .slow,
            "com.github.wez.wezterm": .slow,
            "dev.warp.Warp": .slow,
            "com.mitchellh.ghostty": .slow,
            // Electron editors host terminals (Claude Code CLI) too.
            "com.microsoft.VSCode": .slow,
            "com.todesktop.230313mzl4w4u92": .slow, // Cursor
            "com.tinyspeck.slackmacgap": .slow,
            // Chromium: backspace bursts fight omnibox autocomplete →
            // select-then-retype instead (the OpenKey "Fix Chromium" mechanism).
            "com.google.Chrome": .selectAndRetype,
            "com.microsoft.edgemac": .selectAndRetype,
            "company.thebrowser.Browser": .selectAndRetype, // Arc
            "com.brave.Browser": .selectAndRetype,
            "com.vivaldi.Vivaldi": .selectAndRetype,
            "org.chromium.Chromium": .selectAndRetype,
            "com.coccoc.Coccoc": .selectAndRetype,
            // Launcher overlays type fast into async UIs.
            "com.apple.Spotlight": .slow,
            "com.raycast.macos": .slow,
        ]
        #if DEBUG
        profiles["com.kynguyen.goviet.integration-slow"] = .slow
        profiles["com.kynguyen.goviet.integration-selection"] = .selectAndRetype
        #endif
        return profiles
    }()

    static func strategy(for bundleID: String, overrides: [String: InjectionStrategy]) -> InjectionStrategy {
        overrides[bundleID] ?? defaults[bundleID] ?? .fast
    }
}
