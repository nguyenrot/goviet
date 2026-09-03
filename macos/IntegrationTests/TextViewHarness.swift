import AppKit

/// Minimal native control used by the Debug-only end-to-end typing hook.
/// It prints the final NSTextView contents after the configured timeout so a
/// smoke test can verify the real event tap and injector without UI scraping.
final class HarnessDelegate: NSObject, NSApplicationDelegate {
    private let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 640, height: 320))
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
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
            print(self?.textView.string ?? "")
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
