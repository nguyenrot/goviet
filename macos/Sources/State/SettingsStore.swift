import AppKit
import Combine
import Foundation
import os.log

private let log = Logger(subsystem: "com.kynguyen.goviet", category: "settings")

private enum SettingsSchemaError: LocalizedError {
    case newerVersion(Int)

    var errorDescription: String? {
        switch self {
        case let .newerVersion(version):
            return "config schema \(version) is newer than supported"
        }
    }
}

private func sanitizedSlowDelayMS(_ value: Double) -> Double {
    guard value.isFinite else { return 8.0 }
    return min(max(value, 1.0), 30.0)
}

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

    init() {}

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try values.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        let decodedMethod = try values.decodeIfPresent(String.self, forKey: .method) ?? "telex"
        guard ["telex", "simple_telex", "vni"].contains(decodedMethod) else {
            throw DecodingError.dataCorruptedError(
                forKey: .method,
                in: values,
                debugDescription: "unknown input method \(decodedMethod)"
            )
        }
        method = decodedMethod
        let decodedToneStyle =
            try values.decodeIfPresent(String.self, forKey: .toneStyle) ?? "old"
        guard ["old", "new"].contains(decodedToneStyle) else {
            throw DecodingError.dataCorruptedError(
                forKey: .toneStyle,
                in: values,
                debugDescription: "unknown tone style \(decodedToneStyle)"
            )
        }
        toneStyle = decodedToneStyle
        quickTelex = try values.decodeIfPresent(Bool.self, forKey: .quickTelex) ?? false
        englishAutoRestore =
            try values.decodeIfPresent(Bool.self, forKey: .englishAutoRestore) ?? true
        escRestoresRaw =
            try values.decodeIfPresent(Bool.self, forKey: .escRestoresRaw) ?? true
        autoCapitalize =
            try values.decodeIfPresent(Bool.self, forKey: .autoCapitalize) ?? false
        macrosEnabled =
            try values.decodeIfPresent(Bool.self, forKey: .macrosEnabled) ?? true
    }
}

struct MacroEntry: Codable, Equatable, Identifiable {
    var id = UUID()
    var trigger: String
    var expansion: String

    private enum CodingKeys: String, CodingKey {
        case id
        case trigger
        case expansion
    }

    init(id: UUID = UUID(), trigger: String, expansion: String) {
        self.id = id
        self.trigger = trigger
        self.expansion = expansion
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        trigger = try values.decode(String.self, forKey: .trigger)
        expansion = try values.decode(String.self, forKey: .expansion)
    }
}

struct AppSettings: Codable, Equatable {
    static let currentConfigVersion = 1

    var configVersion = currentConfigVersion
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

    private enum CodingKeys: String, CodingKey {
        case configVersion = "config_version"
        case engine
        case hotkey
        case smartSwitch
        case rememberedMode
        case excludedApps
        case strategyOverrides
        case slowDelayMS
        case macros
        case launchAtLogin
    }

    init() {}

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let decodedVersion = try values.decodeIfPresent(Int.self, forKey: .configVersion) ?? 0
        guard decodedVersion >= 0 else {
            throw DecodingError.dataCorruptedError(
                forKey: .configVersion,
                in: values,
                debugDescription: "config version cannot be negative"
            )
        }
        guard decodedVersion <= Self.currentConfigVersion else {
            throw SettingsSchemaError.newerVersion(decodedVersion)
        }
        configVersion = Self.currentConfigVersion
        engine = try values.decodeIfPresent(EngineConfig.self, forKey: .engine) ?? EngineConfig()
        let decodedHotkey =
            try values.decodeIfPresent(String.self, forKey: .hotkey)
            ?? HotkeyDetector.Chord.ctrlShift.rawValue
        guard HotkeyDetector.Chord(rawValue: decodedHotkey) != nil else {
            throw DecodingError.dataCorruptedError(
                forKey: .hotkey,
                in: values,
                debugDescription: "unknown hotkey \(decodedHotkey)"
            )
        }
        hotkey = decodedHotkey
        smartSwitch = try values.decodeIfPresent(Bool.self, forKey: .smartSwitch) ?? true
        rememberedMode =
            try values.decodeIfPresent([String: Bool].self, forKey: .rememberedMode) ?? [:]
        excludedApps =
            try values.decodeIfPresent([String].self, forKey: .excludedApps) ?? []
        let decodedOverrides =
            try values.decodeIfPresent([String: String].self, forKey: .strategyOverrides) ?? [:]
        guard decodedOverrides.values.allSatisfy({ InjectionStrategy(rawValue: $0) != nil }) else {
            throw DecodingError.dataCorruptedError(
                forKey: .strategyOverrides,
                in: values,
                debugDescription: "unknown injection strategy"
            )
        }
        strategyOverrides = decodedOverrides
        slowDelayMS = sanitizedSlowDelayMS(
            try values.decodeIfPresent(Double.self, forKey: .slowDelayMS) ?? 8.0
        )
        macros = try values.decodeIfPresent([MacroEntry].self, forKey: .macros) ?? []
        launchAtLogin =
            try values.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
    }
}

/// Loads/saves settings and pushes them into the Rust engine + runtime state.
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    @Published private(set) var lastErrorMessage: String?

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
    private var lastLaunchAtLoginRequest: Bool?
    private var persistenceBlocked = false

    func clearError() {
        guard lastErrorMessage != nil else { return }
        lastErrorMessage = nil
        NotificationCenter.default.post(name: .goVietStateChanged, object: nil)
    }

    func reportError(_ context: String, error: Error) {
        reportError("\(context): \(error.localizedDescription)")
    }

    private func reportError(_ message: String) {
        log.error("\(message, privacy: .public)")
        if lastErrorMessage != message {
            lastErrorMessage = message
            NotificationCenter.default.post(name: .goVietStateChanged, object: nil)
        }
    }

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
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            reportError("Không thể tạo thư mục cấu hình", error: error)
        }
        return dir.appendingPathComponent("config.json")
    }

    func load() {
        persistenceBlocked = false
        let url = fileURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            persistAndApply()
            return
        }
        do {
            let data = try Data(contentsOf: url)
            let loaded = try JSONDecoder().decode(AppSettings.self, from: data)
            settings = loaded
        } catch let error as SettingsSchemaError {
            // A downgraded app must not rewrite a newer schema and discard
            // fields it does not understand.
            persistenceBlocked = true
            lastLaunchAtLoginRequest = settings.launchAtLogin
            reportError("Không thể dùng cấu hình", error: error)
            apply()
        } catch {
            reportError("Không thể đọc cấu hình", error: error)
            if let backup = backupUnreadableConfig(at: url) {
                reportError("Đã sao lưu cấu hình lỗi tại \(backup.path)")
                persistAndApply()
            } else {
                // Preserve the original file when a backup cannot be made.
                persistenceBlocked = true
                lastLaunchAtLoginRequest = settings.launchAtLogin
                apply()
            }
        }
    }

    private func backupUnreadableConfig(at url: URL) -> URL? {
        let suffix = UUID().uuidString.lowercased()
        let backup = url.deletingLastPathComponent()
            .appendingPathComponent("config.invalid-\(suffix).json")
        do {
            try FileManager.default.copyItem(at: url, to: backup)
            return backup
        } catch {
            reportError("Không thể sao lưu cấu hình lỗi", error: error)
            return nil
        }
    }

    private func persistAndApply() {
        guard !persistenceBlocked else {
            reportError(
                "Không thể lưu thay đổi: file cấu hình đang được giữ nguyên để tránh mất dữ liệu"
            )
            apply()
            return
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            let data = try encoder.encode(settings)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            reportError("Không thể lưu cấu hình", error: error)
        }
        apply()
    }

    /// Push everything into the engine and runtime — no restart needed.
    func apply() {
        var engine = settings.engine
        engine.enabled = true // the shell gates VN/EN, the engine stays on
        do {
            let data = try JSONEncoder().encode(engine)
            EngineBridge.setConfigJSON(String(decoding: data, as: UTF8.self))
        } catch {
            reportError("Không thể áp dụng cấu hình bộ gõ", error: error)
        }
        let dict = Dictionary(
            settings.macros.map { ($0.trigger, $0.expansion) },
            uniquingKeysWith: { first, _ in first }
        )
        do {
            let data = try JSONEncoder().encode(dict)
            EngineBridge.setMacrosJSON(String(decoding: data, as: UTF8.self))
        } catch {
            reportError("Không thể áp dụng danh sách gõ tắt", error: error)
        }
        HotkeyDetector.shared.setChord(
            HotkeyDetector.Chord(rawValue: settings.hotkey) ?? .ctrlShift
        )
        RuntimeState.shared.slowDelayUS =
            UInt32(sanitizedSlowDelayMS(settings.slowDelayMS) * 1000)
        if lastLaunchAtLoginRequest != settings.launchAtLogin {
            lastLaunchAtLoginRequest = settings.launchAtLogin
            do {
                try LaunchAtLogin.set(enabled: settings.launchAtLogin)
            } catch {
                reportError("Không thể thay đổi Khởi động cùng macOS", error: error)
            }
        }
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
