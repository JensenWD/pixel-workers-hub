import AppKit
import PixelWorkersCore

// One binary, two jobs: the menu-bar app, and (with --pixel-workers-hook) the hook Claude Code runs on
// each session event. The hook returns before any of the app is set up, so it stays quick.
let arguments = Array(CommandLine.arguments.dropFirst())
switch arguments.first {
case HookInstaller.flag?:
    Hook.main()
case "--install-hooks"?:
    do {
        let changed = try HookInstaller.install(executable: Bundle.main.executablePath ?? CommandLine.arguments[0])
        print(changed ? "Claude Code hooks installed." : "Claude Code hooks were already installed.")
    } catch { fail(error) }
case "--remove-hooks"?:
    do {
        let changed = try HookInstaller.remove()
        try? FileManager.default.removeItem(at: Paths.sessions)
        print(changed ? "Claude Code hooks removed." : "No Claude Code hooks to remove.")
    } catch { fail(error) }
case "--list"?:
    // What the panel would show, for troubleshooting.
    let snapshot = Store().load()
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    print(String(decoding: try encoder.encode(snapshot.sessions), as: UTF8.self))
    if let error = snapshot.error { fail(Message(error)) }
case "--open"?:
    // Brings a session's tab forward, as clicking it in the panel does.
    let sessions = Store().load().sessions
    guard arguments.count == 2, let session = sessions.first(where: { $0.id.hasPrefix(arguments[1]) }) else { fail(Message("No open session has that ID. See --list.")) }
    do { try Terminals.focus(session, among: sessions); print("Opened “\(session.name)” in \(session.terminal ?? "its terminal").") }
    catch { fail(error) }
case "--version"?:
    print(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development")
case nil:
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
default:
    print("""
    Usage: PixelWorkersHub [option]
      (no option)       run the menu-bar app
      --install-hooks   add the detailed-status hooks to Claude Code's settings
      --remove-hooks    take them out again
      --list            print the sessions the panel would show
      --open <id>       bring a session's tab forward (an ID prefix from --list will do)
      --version         print the version
    """)
}

func fail(_ error: Error) -> Never {
    FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
    exit(1)
}
