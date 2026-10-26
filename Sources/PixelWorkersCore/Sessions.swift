import Foundation

/// One open Claude Code session, as the panel shows it.
public struct Session: Codable, Equatable {
    public enum Status: String, Codable {
        case working, needsInput = "needs-input", yourTurn = "your-turn", ready, failed, unknown
        /// Statuses that count toward the number beside the menu-bar icon.
        public var needsYou: Bool { self == .needsInput || self == .failed }
    }
    public var id: String
    public var pid: Int32?
    public var name: String
    public var cwd: String
    public var project: String
    /// When its Claude Code process started (ms). It survives /clear, so it keeps a session's place and look.
    public var startedAt: Double
    public var status: Status
    /// When the hook last heard from it (ms), if hooks are on.
    public var since: Double?
    /// The app it runs in, such as Ghostty.
    public var terminal: String?
}

/// A row of `claude agents --json`, Claude Code's own list of what's running.
public struct LiveSession: Decodable, Equatable {
    public var sessionId: String
    public var pid: Int32?
    public var cwd: String?
    public var kind: String?
    public var name: String?
    public var startedAt: Double?
    public var status: String?
    public var state: String?

    public init(sessionId: String, pid: Int32? = nil, cwd: String? = nil, kind: String? = "interactive", name: String? = nil, startedAt: Double? = nil, status: String? = nil) {
        self.sessionId = sessionId; self.pid = pid; self.cwd = cwd; self.kind = kind; self.name = name; self.startedAt = startedAt; self.status = status
    }

    enum Activity { case busy, idle, blocked }
    var activity: Activity? {
        switch (kind == "interactive" ? status : state ?? status)?.lowercased() {
        case "busy", "running", "working": return .busy
        case "idle": return .idle
        // "waiting" is a permission prompt or question on screen; background agents call it "blocked".
        case "waiting", "blocked", "needs_input", "needs-input": return .blocked
        default: return nil
        }
    }
}

public enum Sessions {
    /// Claude Code's own list of interactive sessions. Throws when the CLI can't be found or answered.
    public static func live(claude: String) throws -> [LiveSession] {
        let output = try Command.run(claude, ["agents", "--json"], timeout: 8)
        return try JSONDecoder().decode([LiveSession].self, from: Data(output.utf8))
            .filter { $0.kind == "interactive" && isSessionId($0.sessionId) }
    }

    /// What the panel shows: Claude Code's live list, sharpened by the hook's more specific status when it has one.
    public static func merge(live: [LiveSession], hooks: [String: HookRecord]) -> [Session] {
        live.map { row in
            let cwd = row.cwd ?? ""
            // A status file older than the process belongs to an earlier run that resumed this session.
            let hook = hooks[row.sessionId].flatMap { h in h.updatedAt >= (row.startedAt ?? 0) && h.status != .ended ? h : nil }
            return Session(id: row.sessionId, pid: row.pid, name: Hook.clean(row.name.flatMap { $0.isEmpty ? nil : $0 } ?? hook?.title ?? ""), cwd: cwd,
                           project: project(cwd), startedAt: row.startedAt ?? 0,
                           status: status(row.activity, hook), since: hook?.updatedAt, terminal: nil)
        }.sorted { ($0.startedAt, $0.id) < ($1.startedAt, $1.id) }
    }

    /// Hook files whose Claude process is still running: the list to show when Claude Code can't be asked
    /// (versions before `claude agents`).
    public static func fromHooks(_ hooks: [String: HookRecord],
                                 isAlive: (Int32) -> Bool = Processes.isClaude, started: (Int32) -> Double? = Processes.startTime) -> [Session] {
        // /clear starts a new session in the same process; only its latest is still open.
        var latest: [Int32: Session] = [:]
        for h in hooks.values where h.status != .ended {
            guard let pid = h.pid, (latest[pid]?.since ?? 0) < h.updatedAt, isAlive(pid) else { continue }
            // A file older than the process is from an earlier process that had the same ID.
            let start = started(pid)
            if let start, h.updatedAt < start { continue }
            latest[pid] = Session(id: h.sessionId, pid: pid, name: h.title ?? "", cwd: h.cwd ?? "", project: project(h.cwd ?? ""),
                                  startedAt: start ?? h.updatedAt, status: status(nil, h), since: h.updatedAt, terminal: nil)
        }
        return latest.values.sorted { ($0.startedAt, $0.id) < ($1.startedAt, $1.id) }
    }

    static func project(_ cwd: String) -> String {
        let name = (cwd as NSString).lastPathComponent
        return name.isEmpty ? "Claude Code" : name
    }

    /// The CLI knows what's on screen right now: busy, idle, or waiting on a prompt. The hook knows why
    /// a turn ended. So the CLI decides whenever it has a say, and the hook fills in the rest: a turn that
    /// ended idle was finished, failed or never started. A hook still saying running or needs-input while
    /// Claude is idle missed an Esc (which fires no hook), and that is the user's turn.
    static func status(_ live: LiveSession.Activity?, _ hook: HookRecord?) -> Session.Status {
        switch (live, hook?.status) {
        case (.blocked, _): return .needsInput
        case (.busy, _): return .working
        case (_, .failed?): return .failed
        case (_, .done?): return .yourTurn
        case (_, .ready?): return .ready
        case (.idle, .running?): return hook!.backgroundCount > 0 ? .working : .yourTurn
        case (.idle, _): return .yourTurn
        case (nil, .needsInput?): return .needsInput
        case (nil, .running?): return .working
        default: return .unknown
        }
    }
}
