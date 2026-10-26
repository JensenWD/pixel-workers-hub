import AppKit
import PixelWorkersCore
import ServiceManagement
import WebKit

let repository = URL(string: "https://github.com/JensenWD/pixel-workers-hub")!

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate, NSMenuDelegate {
    private let store = Store()
    private var item: NSStatusItem!
    private let popover = NSPopover()
    private var panel: PanelController!
    private var timer: Timer?
    private var notice: String?
    /// Whether the detailed-status hooks are installed. Checked at launch, when the panel opens and after a
    /// toggle, rather than on every render, since it means reading Claude Code's settings.
    private var hooksOn = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = Icon.menuBar
        item.button?.imagePosition = .imageLeading
        item.button?.target = self
        item.button?.action = #selector(clicked)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        item.button?.toolTip = "Pixel Workers Hub"

        panel = PanelController()
        panel.onMessage = { [weak self] in self?.handle($0) }
        popover.contentViewController = panel
        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self
        popover.appearance = Theme.current.appearance

        store.onChange = { [weak self] in self?.show($0) }
        repairMovedHooks()
        hooksOn = HookInstaller.installedExecutable() != nil
        store.watchHooks()
        store.refresh(full: true)
        schedule(every: 20)
    }

    // MARK: Status item

    @objc private func clicked() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true { return showMenu() }
        if popover.isShown { return popover.performClose(nil) }
        hooksOn = HookInstaller.installedExecutable() != nil
        store.refresh(full: true)
        guard let button = item.button else { return }
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        panel.opened()
    }

    private func showMenu() {
        let menu = optionsMenu()
        item.menu = menu
        item.button?.performClick(nil)
        item.menu = nil
    }

    func popoverDidShow(_ notification: Notification) { schedule(every: 3) }
    func popoverDidClose(_ notification: Notification) { schedule(every: 20) }

    private func schedule(every seconds: TimeInterval) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: true) { [weak self] _ in self?.store.refresh(full: true) }
        timer?.tolerance = seconds / 4
    }

    /// The icon carries a count of sessions that need you: a permission prompt or a failure.
    private func show(_ snapshot: Store.Snapshot) {
        let waiting = snapshot.sessions.filter { $0.status.needsYou }.count
        item.button?.title = waiting > 0 ? " \(waiting)" : ""
        let counts = [("working", Session.Status.working), ("need you", .needsInput), ("failed", .failed), ("your turn", .yourTurn)]
            .map { label, status in (snapshot.sessions.filter { $0.status == status }.count, label) }.filter { $0.0 > 0 }
        item.button?.toolTip = counts.isEmpty ? "Pixel Workers Hub · no sessions" : counts.map { "\($0.0) \($0.1)" }.joined(separator: " · ")
        render()
    }

    private func render() {
        panel.render(store.snapshot, hooks: hooksOn ? "on" : "off", theme: Theme.current, notice: notice)
        notice = nil
    }

    // MARK: Panel messages

    private func handle(_ message: [String: Any]) {
        switch message["type"] as? String {
        case "ready": render()
        case "resize":
            guard let height = message["height"] as? Double else { return }
            let room = (item.button?.window?.screen ?? NSScreen.main)?.visibleFrame.height ?? 800
            // The popover sizes itself from its content's preferred size.
            panel.preferredContentSize = NSSize(width: PanelController.width, height: min(height, room - 40))
        case "focus":
            guard let id = message["id"] as? String else { return }
            store.focus(id) { [weak self] error in
                guard let self else { return }
                if let error {
                    let automation = (error as? FocusError)?.kind == .notAuthorized
                    panel.say(error.localizedDescription, automation: automation)
                } else {
                    popover.performClose(nil)
                }
            }
        case "hooks": toggleHooks()
        case "automation":
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!)
        case "menu":
            let point = NSPoint(x: message["x"] as? Double ?? 0, y: message["y"] as? Double ?? 0)
            optionsMenu().popUp(positioning: nil, at: panel.viewPoint(point), in: panel.view)
        case "close": popover.performClose(nil)
        case "error": NSLog("Panel script error: %@", message["message"] as? String ?? "?")
        default: break
        }
    }

    // MARK: Options

    private func optionsMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: "Refresh", action: #selector(refreshNow), keyEquivalent: "r").target = self
        menu.addItem(.separator())
        let hooks = menu.addItem(withTitle: "Detailed Status (Claude Code Hooks)", action: #selector(toggleHooksItem), keyEquivalent: "")
        hooks.target = self
        hooks.state = hooksOn ? .on : .off
        let appearance = NSMenu()
        for theme in Theme.allCases {
            let choice = appearance.addItem(withTitle: theme.title, action: #selector(chooseTheme(_:)), keyEquivalent: "")
            choice.target = self
            choice.representedObject = theme.rawValue
            choice.state = theme == Theme.current ? .on : .off
        }
        menu.addItem(withTitle: "Appearance", action: nil, keyEquivalent: "").submenu = appearance
        let login = menu.addItem(withTitle: "Open at Login", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(.separator())
        menu.addItem(withTitle: "About Pixel Workers Hub", action: #selector(about), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Quit Pixel Workers Hub", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return menu
    }

    @objc private func refreshNow() { store.refresh(full: true) }

    @objc private func chooseTheme(_ item: NSMenuItem) {
        guard let theme = (item.representedObject as? String).flatMap(Theme.init) else { return }
        Theme.current = theme
        popover.appearance = theme.appearance
        render()
    }
    @objc private func toggleHooksItem() { toggleHooks() }
    @objc private func about() { NSWorkspace.shared.open(repository) }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
        } catch {
            alert("Couldn’t change Open at Login", error.localizedDescription)
        }
    }

    private func toggleHooks() {
        do {
            if HookInstaller.installedExecutable() != nil {
                try HookInstaller.remove()
                try? FileManager.default.removeItem(at: Paths.sessions)
                notice = "Detailed status is off. Hooks were removed from Claude Code’s settings."
            } else {
                guard let executable = Bundle.main.executablePath, !executable.contains("/AppTranslocation/") else {
                    throw Message("Move Pixel Workers Hub to your Applications folder first, then turn this on.")
                }
                try HookInstaller.install(executable: executable)
                notice = "Detailed status is on for Claude Code sessions started from now on. Restart open ones to include them."
            }
        } catch {
            notice = error.localizedDescription
        }
        hooksOn = HookInstaller.installedExecutable() != nil
        // The status folder was just created or removed; watch the one that's there now.
        store.watchHooks()
        store.refresh(full: false)
        // From the menu-bar menu, with the panel closed, the outcome would otherwise go unseen.
        if !popover.isShown, let notice {
            self.notice = nil
            alert(hooksOn ? "Detailed status is on" : "Detailed status is off", notice)
        }
        render()
    }

    /// The hooks run this app by its path; if the app moved since, point them at where it is now.
    private func repairMovedHooks() {
        guard let installed = HookInstaller.installedExecutable(), let here = Bundle.main.executablePath, installed != here,
              !FileManager.default.fileExists(atPath: installed), !here.contains("/AppTranslocation/") else { return }
        _ = try? HookInstaller.install(executable: here)
    }

    private func alert(_ title: String, _ text: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
