import Darwin
import Foundation

/// What the hook remembers about one session. Only this metadata is ever written: prompts, transcripts,
/// tool inputs and outputs, commands and messages in the hook's input are discarded.
public struct HookRecord: Codable, Equatable {
    public enum Status: String, Codable { case ready, running, needsInput = "needs-input", done, failed, ended }
    public var version = 1
    public var sessionId: String
    public var status: Status
    public var event: String
    public var updatedAt: Double // ms since 1970
    public var backgroundCount = 0
    public var pid: Int32?
    public var cwd: String?
    public var title: String?

    public init(sessionId: String, status: Status, event: String, updatedAt: Double) {
        self.sessionId = sessionId; self.status = status; self.event = event; self.updatedAt = updatedAt
    }
}

public func isSessionId(_ id: String) -> Bool {
    !id.isEmpty && id.count <= 100 && id.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
}

/// Claude Code runs this for each lifecycle event (`PixelWorkersHub --pixel-workers-hook`). It must be quick, silent
/// and never fail Claude: every problem is swallowed.
public enum Hook {
    public static let events = ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PostToolUseFailure",
                                "PermissionRequest", "Notification", "Stop", "StopFailure", "SessionEnd"]
    public static let notifications = ["permission_prompt", "elicitation_dialog", "elicitation_url_dialog", "idle_prompt"]

    public static func main() {
        // Bound memory without truncating a body into a misleading valid event.
        let limit = 2 * 1024 * 1024
        let raw = FileHandle.standardInput.readData(ofLength: limit + 1)
        guard raw.count <= limit, let input = try? JSONSerialization.jsonObject(with: raw) as? [String: Any] else { return }
        try? record(input, in: Paths.sessions, claudePid: claudeProcess())
    }

    /// The Claude Code process that ran this hook (through a shell or two).
    static func claudeProcess() -> Int32? {
        Processes.lineage(of: getppid(), limit: 8).first(where: Processes.isClaude)
    }

    /// The status a hook event leaves the session in, given the one it was in.
    public static func status(after input: [String: Any], previous: HookRecord.Status?) -> HookRecord.Status? {
        switch input["hook_event_name"] as? String {
        case "SessionStart": return .ready
        case "UserPromptSubmit", "PreToolUse", "PostToolUse", "PostToolUseFailure": return .running
        case "PermissionRequest": return .needsInput
        case "Stop":
            // Background tasks keep the session working after the turn ends.
            return ((input["background_tasks"] as? [Any])?.isEmpty == false) ? .running : .done
        case "StopFailure": return .failed
        case "SessionEnd": return .ended
        case "Notification":
            // Claude has been idle a while: that doesn't change what it last did.
            if input["notification_type"] as? String == "idle_prompt" { return previous ?? .ready }
            return .needsInput
        default: return nil
        }
    }

    public static func record(_ input: [String: Any], in directory: URL, claudePid: Int32?, now: Date = Date()) throws {
        guard let event = input["hook_event_name"] as? String, events.contains(event),
              let sid = input["session_id"] as? String, isSessionId(sid) else { return }
        // Tool hooks from an in-process subagent share the parent's session ID.
        if input["agent_id"] != nil { return }
        if event == "Notification", !notifications.contains(input["notification_type"] as? String ?? "") { return }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let lock = open(directory.appendingPathComponent(".lock").path, O_CREAT | O_RDWR, 0o600)
        guard lock >= 0 else { return }
        defer { close(lock) }
        flock(lock, LOCK_EX)

        let file = directory.appendingPathComponent(sid + ".json")
        let previous = (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode(HookRecord.self, from: $0) }
        // Claude has been idle a while: nothing happened, so the record stays as it was. Touching its time
        // would make an old status look newer than Claude Code's own list.
        if event == "Notification", input["notification_type"] as? String == "idle_prompt", previous != nil { return }
        guard let status = status(after: input, previous: event == "SessionStart" ? nil : previous?.status) else { return }
        var row = HookRecord(sessionId: sid, status: status, event: event, updatedAt: (now.timeIntervalSince1970 * 1000).rounded())
        row.pid = claudePid ?? previous?.pid
        row.cwd = (input["cwd"] as? String).map(clean) ?? previous?.cwd
        row.title = (input["session_title"] as? String).map { String(clean($0).prefix(100)) } ?? previous?.title
        if event == "Stop" { row.backgroundCount = (input["background_tasks"] as? [Any])?.count ?? 0 }
        else if event == "Notification" { row.backgroundCount = previous?.backgroundCount ?? 0 }

        let temp = directory.appendingPathComponent(".\(sid).\(getpid()).tmp")
        try JSONEncoder().encode(row).write(to: temp)
        if rename(temp.path, file.path) != 0 { try? FileManager.default.removeItem(at: temp) }
    }

    static func clean(_ text: String) -> String {
        String(text.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) })
    }

    /// Every session the hook has seen, skipping anything unreadable.
    public static func records(in directory: URL = Paths.sessions) -> [String: HookRecord] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        var rows: [String: HookRecord] = [:]
        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file), data.count < 16_384,
                  let row = try? JSONDecoder().decode(HookRecord.self, from: data),
                  row.version == 1, row.sessionId + ".json" == file.lastPathComponent else { continue }
            rows[row.sessionId] = row
        }
        return rows
    }

    /// Forgets sessions that haven't reported in a week.
    public static func prune(_ directory: URL = Paths.sessions, now: Date = Date()) {
        let cutoff = (now.timeIntervalSince1970 - 7 * 86_400) * 1000
        for (id, row) in records(in: directory) where row.updatedAt < cutoff {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(id + ".json"))
        }
    }
}
