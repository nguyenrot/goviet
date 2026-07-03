import AppKit
import Combine
import Foundation

/// Mirror of the Rust engine Config — field names must match serde exactly.
struct EngineConfig: Codable, Equatable {
    var enabled = true
    var method = "telex" // telex | simple_telex | vni
    var toneStyle = "old" // old | new
    var quickTelex = false
    var englishAutoRestore = true
    var escRestoresRaw = true
    var autoCapitalize = false
    var macrosEnabled = true

    enum CodingKeys: String, CodingKey {
        case enabled
        case method
        case toneStyle = "tone_style"
        case quickTelex = "quick_telex"
        case englishAutoRestore = "english_auto_restore"
        case escRestoresRaw = "esc_restores_raw"
        case autoCapitalize = "auto_capitalize"
        case macrosEnabled = "macros_enabled"
    }
}

struct MacroEntry: Codable, Equatable, Identifiable {
    var id = UUID()
    var trigger: String
    var expansion: String
}

struct AppSettings: Codable, Equatable {
    var engine = EngineConfig()
    var hotkey = HotkeyDetector.Chord.ctrlShift.rawValue
    /// Remember VN/EN per app and restore it on app switch.
    var smartSwitch = true
    var rememberedMode: [String: Bool] = [:]
    var excludedApps: [String] = []
    var strategyOverrides: [String: String] = [:]
    var slowDelayMS = 8.0
    var macros: [MacroEntry] = []
    var launchAtLogin = false
}

/// Loads/saves settings and pushes them into the Rust engine + runtime state.
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    @Published var settings = AppSettings() {
        didSet { persistAndApply() }
    }

    /// Global VN/EN state (the hotkey flips this; not persisted per se).
    @Published var vietnameseOn = true {
        didSet {
            RuntimeState.shared.vietnameseOn = vietnameseOn
            EngineBridge.clearAll()
            if !quiet, settings.smartSwitch {
                let bundle = RuntimeState.shared.frontBundleID
                if !bundle.isEmpty, settings.rememberedMode[bundle] != vietnameseOn {
                    settings.rememberedMode[bundle] = vietnameseOn
                }
            }
            NotificationCenter.default.post(name: .goVietStateChanged, object: nil)
        }
    }

    private var quiet = false

    /// Restore a remembered per-app mode without re-recording it.
    func setVietnameseOnQuietly(_ on: Bool) {
        guard vietnameseOn != on else { return }
        quiet = true
        vietnameseOn = on
        quiet = false
    }

    private var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GoViet", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("config.json")
    }

    func load() {
        if let data = try? Data(contentsOf: fileURL),
           let loaded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            settings = loaded
        } else {
            persistAndApply()
        }
    }

    private func persistAndApply() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(settings) {
            try? data.write(to: fileURL, options: .atomic)
        }
        apply()
    }

    /// Push everything into the engine and runtime — no restart needed.
    func apply() {
        var engine = settings.engine
        engine.enabled = true // the shell gates VN/EN, the engine stays on
        if let data = try? JSONEncoder().encode(engine),
           let json = String(data: data, encoding: .utf8) {
            EngineBridge.setConfigJSON(json)
        }
        let dict = Dictionary(
            settings.macros.map { ($0.trigger, $0.expansion) },
            uniquingKeysWith: { first, _ in first }
        )
        if let data = try? JSONEncoder().encode(dict),
           let json = String(data: data, encoding: .utf8) {
            EngineBridge.setMacrosJSON(json)
        }
        HotkeyDetector.shared.setChord(
            HotkeyDetector.Chord(rawValue: settings.hotkey) ?? .ctrlShift
        )
        RuntimeState.shared.slowDelayUS = UInt32(max(1, settings.slowDelayMS) * 1000)
        LaunchAtLogin.set(enabled: settings.launchAtLogin)
        AppMonitor.shared.refresh()
        NotificationCenter.default.post(name: .goVietStateChanged, object: nil)
    }

    // MARK: - Macro import/export

    func exportMacros(to url: URL) throws {
        let dict = Dictionary(
            settings.macros.map { ($0.trigger, $0.expansion) },
            uniquingKeysWith: { first, _ in first }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(dict).write(to: url, options: .atomic)
    }

    func importMacros(from url: URL) throws {
        let data = try Data(contentsOf: url)
        let dict = try JSONDecoder().decode([String: String].self, from: data)
        var merged = settings.macros.filter { dict[$0.trigger] == nil }
        merged.append(contentsOf: dict.map { MacroEntry(trigger: $0.key, expansion: $0.value) })
        settings.macros = merged.sorted { $0.trigger < $1.trigger }
    }
}

extension Notification.Name {
    static let goVietStateChanged = Notification.Name("goviet.stateChanged")
}
