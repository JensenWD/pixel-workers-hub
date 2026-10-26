// Renders the panel with made-up sessions into docs/panel-light.png and docs/panel-dark.png, for the README.
// Run with `make screenshot` from the repository root.
import AppKit
import WebKit

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let now = Date().timeIntervalSince1970 * 1000
let minute = 60_000.0
let demo: [[String: Any]] = [
    ["id": "a", "pid": 101, "name": "Fix the flaky login test", "project": "web-app", "terminal": "Ghostty", "status": "needs-input", "startedAt": 1, "since": now - 2 * minute],
    ["id": "b", "pid": 102, "name": "Migrate billing to Stripe", "project": "api", "terminal": "Ghostty", "status": "working", "startedAt": 2, "since": now - 0.2 * minute],
    ["id": "c", "pid": 103, "name": "Dark mode for settings", "project": "web-app", "terminal": "Ghostty", "status": "your-turn", "startedAt": 3, "since": now - 14 * minute],
    ["id": "d", "pid": 104, "name": "Release notes for 2.4", "project": "docs", "terminal": "iTerm2", "status": "failed", "startedAt": 4, "since": now - 41 * minute],
    ["id": "e", "pid": 105, "name": "", "project": "scratch", "terminal": "Ghostty", "status": "ready", "startedAt": 5, "since": now - 1 * minute],
]

final class Shooter: NSObject, WKNavigationDelegate {
    let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 360, height: 600))
    let window = NSWindow(contentRect: NSRect(x: -2000, y: 0, width: 360, height: 600), styleMask: .borderless, backing: .buffered, defer: false)
    var themes = ["light", "dark"]

    func start() {
        window.contentView = web
        window.orderFrontRegardless()
        web.navigationDelegate = self
        next()
    }

    func next() {
        guard let theme = themes.first else { return NSApp.terminate(nil) }
        window.appearance = NSAppearance(named: theme == "dark" ? .darkAqua : .aqua)
        let page = root.appendingPathComponent("Web/panel.html")
        web.loadFileURL(page, allowingReadAccessTo: page.deletingLastPathComponent())
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let data = try! JSONSerialization.data(withJSONObject: ["sessions": demo, "hooks": "on", "now": now])
        web.evaluateJavaScript("render(\(String(decoding: data, as: UTF8.self))); document.body.getBoundingClientRect().height") { height, _ in
            let height = (height as? Double) ?? 500
            self.window.setContentSize(NSSize(width: 360, height: height))
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { self.shoot() }
        }
    }

    func shoot() {
        web.takeSnapshot(with: nil) { image, _ in
            let theme = self.themes.removeFirst()
            if let tiff = image?.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                try! FileManager.default.createDirectory(at: root.appendingPathComponent("docs"), withIntermediateDirectories: true)
                try! png.write(to: root.appendingPathComponent("docs/panel-\(theme).png"))
                print("Wrote docs/panel-\(theme).png")
            }
            self.next()
        }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let shooter = Shooter()
shooter.start()
app.run()
