import AppKit
import Foundation

public struct FocusError: LocalizedError {
    public enum Kind { case notAuthorized, notFound, notRunning, failed }
    public let kind: Kind
    public let errorDescription: String?
    public let app: String?
    init(_ kind: Kind, _ message: String, app: String? = nil) { self.kind = kind; errorDescription = message; self.app = app }
}

/// Brings a session's terminal tab to the front.
///
/// Ghostty doesn't say which process runs in a tab, but Claude Code titles its tab with the session's name
/// ("✳ fix the login bug", with a spinner glyph while it works) and the tab knows its folder. iTerm2 and
/// Terminal know each tab's tty, which is exact. Any other app (VS Code, Warp, WezTerm…) is brought forward.
public enum Terminals {
    public static let ghostty = "com.mitchellh.ghostty", iterm = "com.googlecode.iterm2", terminal = "com.apple.Terminal"

    /// The app a process runs under: its nearest ancestor that's a regular app. tmux and screen detach
    /// their sessions from the terminal, so those come back nil.
    public static func host(of pid: Int32) -> NSRunningApplication? {
        for ancestor in Processes.lineage(of: pid).dropFirst() {
            if let app = NSRunningApplication(processIdentifier: ancestor), app.bundleIdentifier != nil { return app }
        }
        return nil
    }

    public static func focus(_ session: Session, among sessions: [Session]) throws {
        let app = session.pid.flatMap(host(of:))
        switch app?.bundleIdentifier {
        case ghostty?: try focusGhostty(session, among: sessions)
        case iterm?, terminal?:
            guard let pid = session.pid, let tty = Processes.tty(of: pid) else { throw FocusError(.notFound, "Couldn't find this session's tab.") }
            try run(app!.bundleIdentifier == iterm ? itermScript : terminalScript, [tty], app: app!.localizedName ?? "the terminal")
        case _? where app != nil:
            app!.activate()
        default:
            // Under tmux the terminal isn't an ancestor; Ghostty can still be searched by title.
            if NSRunningApplication.runningApplications(withBundleIdentifier: ghostty).isEmpty {
                throw FocusError(.notFound, "Couldn't tell which terminal this session runs in.")
            }
            try focusGhostty(session, among: sessions)
        }
    }

    // MARK: Ghostty

    public struct GhosttyTab: Equatable {
        public var id, title, dir: String
        public init(id: String, title: String, dir: String) { self.id = id; self.title = title; self.dir = dir }
    }

    /// The title without Claude Code's status glyph, for comparing with a session's name.
    static func bare(_ title: String) -> String {
        String(title.drop { !$0.isLetter && !$0.isNumber }).trimmingCharacters(in: .whitespaces).lowercased()
    }

    /// The tab titled with the session's name, preferring one in its folder. Failing that, the one tab in its
    /// folder that looks like Claude Code (a status glyph, or the default "Claude Code" title) and isn't
    /// titled for a different session.
    public static func pick(_ tabs: [GhosttyTab], for session: Session, among sessions: [Session]) -> GhosttyTab? {
        let name = bare(session.name)
        let named = name.isEmpty ? [] : tabs.filter { bare($0.title) == name }
        if !named.isEmpty { return named.first { $0.dir == session.cwd } ?? named[0] }
        let others = Set(sessions.filter { $0.id != session.id }.map { bare($0.name) }.filter { !$0.isEmpty })
        let candidates = tabs.filter { tab in
            guard tab.dir == session.cwd, !others.contains(bare(tab.title)) else { return false }
            return bare(tab.title) == "claude code" || tab.title.first.map { !$0.isLetter && !$0.isNumber && !$0.isWhitespace && $0 != "~" && $0 != "/" } == true
        }
        return candidates.count == 1 ? candidates[0] : nil
    }

    static func focusGhostty(_ session: Session, among sessions: [Session]) throws {
        let listed = try run(ghosttyList, [], app: "Ghostty")
        let tabs = listed.split(separator: "\n").compactMap { line -> GhosttyTab? in
            let parts = line.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
            return parts.count == 3 ? GhosttyTab(id: parts[0], title: parts[1], dir: parts[2]) : nil
        }
        guard let tab = pick(tabs, for: session, among: sessions),
              try run(ghosttyFocus, [tab.id], app: "Ghostty") == "ok" else {
            throw FocusError(.notFound, session.name.isEmpty ? "No Ghostty tab looks like this session." : "No Ghostty tab is titled “\(session.name)”.")
        }
    }

    // Values reach the scripts as arguments, never written into them.
    static let ghosttyList = """
    on run argv
      -- Inside the tell block, "tab" means one of Ghostty's tabs, so the separator is named out here.
      set sep to character id 9
      set out to ""
      tell application id "com.mitchellh.ghostty"
        repeat with t in terminals
          set out to out & (id of t) & sep & (name of t) & sep & (working directory of t) & linefeed
        end repeat
      end tell
      return out
    end run
    """
    static let ghosttyFocus = """
    on run argv
      tell application id "com.mitchellh.ghostty"
        repeat with t in terminals
          if (id of t) is (item 1 of argv) then
            focus t
            activate
            return "ok"
          end if
        end repeat
      end tell
      return "gone"
    end run
    """
    static let itermScript = """
    on run argv
      tell application id "com.googlecode.iterm2"
        repeat with w in windows
          repeat with t in tabs of w
            repeat with s in sessions of t
              if (tty of s) is (item 1 of argv) then
                select w
                select t
                select s
                activate
                return "ok"
              end if
            end repeat
          end repeat
        end repeat
      end tell
      error "not found" number -1728
    end run
    """
    static let terminalScript = """
    on run argv
      tell application id "com.apple.Terminal"
        repeat with w in windows
          repeat with t in tabs of w
            if (tty of t) is (item 1 of argv) then
              set selected of t to true
              set index of w to 1
              activate
              return "ok"
            end if
          end repeat
        end repeat
      end tell
      error "not found" number -1728
    end run
    """

    @discardableResult
    static func run(_ script: String, _ arguments: [String], app: String) throws -> String {
        do { return try Command.run("/usr/bin/osascript", ["-e", script, "--"] + arguments, timeout: 6).trimmingCharacters(in: .whitespacesAndNewlines) }
        catch let error as CommandError {
            // -1743: macOS's Automation permission was declined.
            if error.stderr.contains("-1743") || error.stderr.localizedCaseInsensitiveContains("not authori") {
                throw FocusError(.notAuthorized, "macOS blocked Pixel Workers Hub from switching \(app) tabs. Allow it under Privacy & Security → Automation.", app: app)
            }
            if error.stderr.contains("-600") || error.stderr.contains("isn’t running") { throw FocusError(.notRunning, "\(app) is not open.", app: app) }
            if error.stderr.contains("-1728") { throw FocusError(.notFound, "Couldn't find this session's tab in \(app).", app: app) }
            throw FocusError(.failed, "\(app) didn't answer.", app: app)
        }
    }
}
