import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        TabView {
            GeneralTab(store: store)
                .tabItem { Label("Chung", systemImage: "gearshape") }
            TypingTab(store: store)
                .tabItem { Label("Gõ phím", systemImage: "keyboard") }
            MacrosTab(store: store)
                .tabItem { Label("Gõ tắt", systemImage: "text.badge.plus") }
            AppsTab(store: store)
                .tabItem { Label("Ứng dụng", systemImage: "app.badge") }
            AboutTab()
                .tabItem { Label("Giới thiệu", systemImage: "info.circle") }
        }
        .frame(width: 560, height: 420)
        .padding()
        .alert(
            "Lỗi GõViệt",
            isPresented: Binding(
                get: { store.lastErrorMessage != nil },
                set: { if !$0 { store.clearError() } }
            )
        ) {
            Button("OK", role: .cancel) { store.clearError() }
        } message: {
            Text(store.lastErrorMessage ?? "")
        }
    }
}

struct GeneralTab: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        Form {
            Toggle("Bật tiếng Việt", isOn: $store.vietnameseOn)
            Picker("Phím tắt chuyển Anh–Việt", selection: $store.settings.hotkey) {
                ForEach(HotkeyDetector.Chord.allCases, id: \.rawValue) { chord in
                    Text(chord.display).tag(chord.rawValue)
                }
            }
            if store.settings.hotkey == HotkeyDetector.Chord.fn.rawValue {
                Text("Nếu phím 🌐 vẫn mở bảng emoji hoặc đổi nguồn nhập, hãy đặt “Nhấn phím 🌐 để” thành “Không làm gì” trong Cài đặt hệ thống → Bàn phím.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Toggle("Nhớ chế độ Anh/Việt theo từng ứng dụng", isOn: $store.settings.smartSwitch)
            Toggle("Khởi động cùng macOS", isOn: $store.settings.launchAtLogin)
            Spacer()
        }
        .padding()
    }
}

struct TypingTab: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        Form {
            Picker("Kiểu gõ", selection: $store.settings.engine.method) {
                Text("Telex").tag("telex")
                Text("VNI").tag("vni")
                Text("Simple Telex").tag("simple_telex")
            }
            Picker("Vị trí dấu thanh", selection: $store.settings.engine.toneStyle) {
                Text("Kiểu cũ (òa, úy)").tag("old")
                Text("Kiểu mới (oà, uý)").tag("new")
            }
            Toggle("Tự khôi phục từ tiếng Anh (add → add, không thành ađ)", isOn: $store.settings.engine.englishAutoRestore)
            Toggle("Phím ESC trả lại phím gốc đã gõ", isOn: $store.settings.engine.escRestoresRaw)
            Toggle("Tự viết hoa đầu câu", isOn: $store.settings.engine.autoCapitalize)
            Toggle("Gõ nhanh phụ âm (cc→ch, gg→gi, kk→kh…)", isOn: $store.settings.engine.quickTelex)
            Spacer()
        }
        .padding()
    }
}

struct MacrosTab: View {
    @ObservedObject var store: SettingsStore
    @State private var selection: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Bật gõ tắt", isOn: $store.settings.engine.macrosEnabled)
            Table($store.settings.macros, selection: $selection) {
                TableColumn("Gõ tắt") { $entry in
                    TextField("vd: btw", text: $entry.trigger)
                }
                .width(120)
                TableColumn("Thay bằng") { $entry in
                    TextField("vd: by the way", text: $entry.expansion)
                }
            }
            HStack {
                Button {
                    store.settings.macros.append(MacroEntry(trigger: "", expansion: ""))
                } label: { Image(systemName: "plus") }
                Button {
                    if let sel = selection {
                        store.settings.macros.removeAll { $0.id == sel }
                        selection = nil
                    }
                } label: { Image(systemName: "minus") }
                .disabled(selection == nil)
                Spacer()
                Button("Nhập JSON…") { importMacros() }
                Button("Xuất JSON…") { exportMacros() }
            }
        }
        .padding()
    }

    private func importMacros() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try store.importMacros(from: url)
            } catch {
                store.reportError("Không thể nhập danh sách gõ tắt", error: error)
            }
        }
    }

    private func exportMacros() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "goviet-macros.json"
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try store.exportMacros(to: url)
            } catch {
                store.reportError("Không thể xuất danh sách gõ tắt", error: error)
            }
        }
    }
}

struct AppsTab: View {
    @ObservedObject var store: SettingsStore
    @State private var selection: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("GõViệt tắt hẳn trong các ứng dụng sau (game, app xung đột):")
            List(store.settings.excludedApps, id: \.self, selection: $selection) { bundle in
                Text(bundle)
            }
            HStack {
                Menu("Thêm ứng dụng đang chạy…") {
                    ForEach(runningApps(), id: \.0) { bundle, name in
                        Button("\(name) — \(bundle)") {
                            if !store.settings.excludedApps.contains(bundle) {
                                store.settings.excludedApps.append(bundle)
                            }
                        }
                    }
                }
                .frame(width: 220)
                Button {
                    if let sel = selection {
                        store.settings.excludedApps.removeAll { $0 == sel }
                        selection = nil
                    }
                } label: { Image(systemName: "minus") }
                .disabled(selection == nil)
                Spacer()
            }
            Divider()
            HStack {
                Text("Độ trễ bơm phím tương thích (ms)")
                Slider(value: $store.settings.slowDelayMS, in: 1...30, step: 1)
                Text("\(Int(store.settings.slowDelayMS))")
                    .frame(width: 30)
            }
        }
        .padding()
    }

    private func runningApps() -> [(String, String)] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app in
                guard let bundle = app.bundleIdentifier else { return nil }
                return (bundle, app.localizedName ?? bundle)
            }
            .sorted { $0.1 < $1.1 }
    }
}

struct AboutTab: View {
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    var body: some View {
        VStack(spacing: 10) {
            Text("GõViệt").font(.largeTitle.bold())
            Text("Bộ gõ tiếng Việt cho macOS — kiểu Unikey")
            Text("Phiên bản \(version)").foregroundStyle(.secondary)
            Text("Engine Rust + shell Swift · MIT License")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
