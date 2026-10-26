import AppKit
import PixelWorkersCore
import WebKit

/// The popover's content: the panel page (Web/) in a web view. The app sends it the session list; the
/// page sends back what was clicked.
final class PanelController: NSViewController, WKScriptMessageHandler, WKNavigationDelegate {
    static let width: CGFloat = 360
    var onMessage: (([String: Any]) -> Void)?
    private var web: WKWebView!

    override func loadView() {
        let config = WKWebViewConfiguration()
        // A weak hop, since the content controller would otherwise keep this controller alive.
        config.userContentController.add(WeakHandler(self), name: "app")
        web = WKWebView(frame: NSRect(x: 0, y: 0, width: Self.width, height: 300), configuration: config)
        web.navigationDelegate = self
        web.setValue(false, forKey: "drawsBackground")
        view = web
        preferredContentSize = web.frame.size
        if let page = Self.page {
            web.loadFileURL(page, allowingReadAccessTo: page.deletingLastPathComponent())
        }
    }

    /// Bundled in the app's Resources; `swift run` reads it straight from the source tree.
    static var page: URL? {
        if let bundled = Bundle.main.url(forResource: "panel", withExtension: "html", subdirectory: "web") { return bundled }
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../Web/panel.html").standardized
        return FileManager.default.fileExists(atPath: source.path) ? source : nil
    }

    func render(_ snapshot: Store.Snapshot, hooks: String, theme: Theme, notice: String?) {
        var data: [String: Any] = [
            "sessions": (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot.sessions))) ?? [],
            "hooks": hooks,
            "theme": theme.rawValue,
            "now": (Date().timeIntervalSince1970 * 1000).rounded(),
        ]
        if let error = snapshot.error { data["error"] = error }
        if let notice { data["notice"] = notice }
        call("render", data)
    }

    func say(_ message: String, automation: Bool) { call("say", message, automation) }
    func opened() { call("opened") }

    /// A point from the page (top-left origin) in the web view's own coordinates.
    func viewPoint(_ point: NSPoint) -> NSPoint {
        web.isFlipped ? point : NSPoint(x: point.x, y: web.bounds.height - point.y)
    }

    private func call(_ function: String, _ arguments: Any...) {
        guard let json = try? JSONSerialization.data(withJSONObject: arguments, options: [.fragmentsAllowed]) else { return }
        web?.evaluateJavaScript("window.\(function) && window.\(function)(...\(String(decoding: json, as: UTF8.self)))") { _, error in
            if let error { NSLog("Panel %@ failed: %@", function, String(describing: error)) }
        }
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        if let body = message.body as? [String: Any] { onMessage?(body) }
    }

    // Only the panel itself loads here.
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        decisionHandler(action.request.url?.isFileURL == true ? .allow : .cancel)
    }
}

private final class WeakHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ target: WKScriptMessageHandler) { self.target = target }
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(controller, didReceive: message)
    }
}

/// The panel's look: light unless chosen otherwise in Options → Appearance.
enum Theme: String, CaseIterable {
    case light, dark, system
    static var current: Theme {
        get { UserDefaults.standard.string(forKey: "theme").flatMap(Theme.init) ?? .light }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "theme") }
    }
    var title: String { self == .system ? "Match System" : rawValue.capitalized }
    /// For the popover's own frame and arrow.
    var appearance: NSAppearance? {
        switch self {
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        case .system: return nil
        }
    }
}

enum Icon {
    /// A pixel worker at a monitor, drawn as a template image so it follows the menu bar's colours.
    static let menuBar: NSImage = {
        let rows = [
            ".........#######",
            "..###....#.....#",
            ".#####...#.....#",
            ".#####...#.....#",
            ".#####...#.....#",
            "..###....#######",
            "............#...",
            ".#####.....###..",
            "#######.........",
            "################",
            ".#............#.",
            ".#............#.",
            ".#............#.",
        ]
        let size = NSSize(width: rows[0].count, height: rows.count)
        let image = NSImage(size: size, flipped: true) { _ in
            NSColor.black.setFill()
            for (y, row) in rows.enumerated() {
                for (x, c) in row.enumerated() where c == "#" { NSRect(x: x, y: y, width: 1, height: 1).fill() }
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Pixel Workers Hub"
        return image
    }()
}
