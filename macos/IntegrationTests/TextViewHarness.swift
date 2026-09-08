import AppKit

private final class HarnessTextView: NSTextView {
    var shortcutCounts = ["copy": 0, "paste": 0, "selectAll": 0]

    override func copy(_ sender: Any?) {
        shortcutCounts["copy", default: 0] += 1
        super.copy(sender)
    }

    override func paste(_ sender: Any?) {
        shortcutCounts["paste", default: 0] += 1
        super.paste(sender)
    }

    override func selectAll(_ sender: Any?) {
        shortcutCounts["selectAll", default: 0] += 1
        super.selectAll(sender)
    }

    override func keyDown(with event: NSEvent) {
        // This programmatic harness has no nib/application menu controller.
        // Handle the delivered shortcuts explicitly, then exercise NSTextView's
        // actual editing and clipboard actions. A missing/stripped Command
        // event must fail the counter assertions rather than silently pass.
        if event.modifierFlags.contains(.command) {
            switch event.keyCode {
            case 0: selectAll(nil)
            case 8: copy(nil)
            case 9: paste(nil)
            default: super.keyDown(with: event)
            }
        } else {
            super.keyDown(with: event)
        }
        if ProcessInfo.processInfo.environment["GOVIET_HARNESS_TRACE"] == "1" {
            let record: [String: Any] = [
                "keycode": event.keyCode,
                "flags": event.modifierFlags.rawValue,
                "characters": event.characters ?? "",
                "text": string,
            ]
            if let data = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]) {
                FileHandle.standardError.write(data + Data([10]))
            }
        }
    }
}

/// Minimal native control used by the Debug-only end-to-end typing hook.
/// It prints the final NSTextView contents after the configured timeout so a
/// smoke test can verify the real event tap and injector without UI scraping.
final class HarnessDelegate: NSObject, NSApplicationDelegate {
    private let textView = HarnessTextView(frame: NSRect(x: 0, y: 0, width: 640, height: 320))
    private var window: NSWindow?
    private var clipboardItems: [[NSPasteboard.PasteboardType: Data]] = []
    private var resignCount = 0
    private var eventMonitor: Any?

    func applicationDidResignActive(_ notification: Notification) {
        resignCount += 1
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if ProcessInfo.processInfo.environment["GOVIET_HARNESS_TRACE"] == "1" {
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { event in
                let record: [String: Any] = [
                    "eventType": event.type.rawValue, "keycode": event.keyCode,
                    "flags": event.modifierFlags.rawValue,
                    "characters": event.type == .flagsChanged ? "" : (event.characters ?? ""),
                ]
                if let data = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]) {
                    FileHandle.standardError.write(data + Data([10]))
                }
                return event
            }
        }
        if ProcessInfo.processInfo.environment["GOVIET_HARNESS_SHORTCUTS"] == "1" {
            clipboardItems = (NSPasteboard.general.pasteboardItems ?? []).map { item in
                Dictionary(uniqueKeysWithValues: item.types.compactMap { type in
                    item.data(forType: type).map { (type, $0) }
                })
            }
        }
        // Assert the IME's output without native spelling/text substitutions
        // introducing unrelated edits.
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 320),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.title = "GoViet Integration Harness"
        window.contentView = textView
        window.makeFirstResponder(textView)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window

        let timeout = Double(ProcessInfo.processInfo.environment["GOVIET_HARNESS_SECONDS"] ?? "8") ?? 8
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
            guard let self else { return }
            if ProcessInfo.processInfo.environment["GOVIET_HARNESS_SHORTCUTS"] == "1" {
                let result: [String: Any] = [
                    "text": self.textView.string,
                    "shortcuts": self.textView.shortcutCounts,
                    "resignCount": self.resignCount,
                ]
                let data = try! JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
                print(String(decoding: data, as: UTF8.self))
                let items = self.clipboardItems.map { values in
                    let item = NSPasteboardItem()
                    for (type, data) in values { item.setData(data, forType: type) }
                    return item
                }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.writeObjects(items)
            } else {
                print(self.textView.string)
            }
            fflush(stdout)
            NSApp.terminate(nil)
        }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = HarnessDelegate()
app.delegate = delegate
app.run()
