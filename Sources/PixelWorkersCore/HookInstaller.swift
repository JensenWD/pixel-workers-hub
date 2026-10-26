import Foundation
import JavaScriptCore

/// Adds or removes Pixel Workers Hub's hooks in Claude Code's settings.json, leaving everything else as it was.
/// A copy of the previous file is kept under ~/Library/Application Support/Pixel Workers Hub/backups.
public enum HookInstaller {
    /// Marks Pixel Workers Hub's own hook commands, wherever the app lives.
    public static let flag = "--pixel-workers-hook"

    public static func command(for executable: String) -> String {
        "'" + executable.replacingOccurrences(of: "'", with: "'\\''") + "' " + flag + " >/dev/null 2>&1 || true"
    }

    /// The app path the installed hooks run, or nil when none are installed.
    public static func installedExecutable(settings: URL = Paths.claudeSettings) -> String? {
        guard let data = try? Data(contentsOf: settings), let text = String(data: data, encoding: .utf8),
              let found = try? transform(text, command: nil, mode: "find"), !found.isEmpty else { return nil }
        // 'path' --pixel-workers-hook …, with ' written as '\''
        guard found.hasPrefix("'"), let end = found.range(of: "' " + flag) else { return found }
        return String(found[found.index(after: found.startIndex)..<end.lowerBound]).replacingOccurrences(of: "'\\''", with: "'")
    }

    /// Returns false when nothing needed to change.
    @discardableResult
    public static func install(executable: String, settings: URL = Paths.claudeSettings, backups: URL = Paths.backups) throws -> Bool {
        try update(settings: settings, backups: backups, command: command(for: executable), mode: "install")
    }

    @discardableResult
    public static func remove(settings: URL = Paths.claudeSettings, backups: URL = Paths.backups) throws -> Bool {
        try update(settings: settings, backups: backups, command: nil, mode: "remove")
    }

    static func update(settings: URL, backups: URL, command: String?, mode: String) throws -> Bool {
        let fm = FileManager.default
        let original = try? Data(contentsOf: settings)
        let text = original.map { String(decoding: $0, as: UTF8.self) } ?? "{}"
        let updated = try transform(text, command: command, mode: mode)
        if updated == text || original == nil && mode == "remove" { return false }

        try fm.createDirectory(at: settings.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let original {
            try fm.createDirectory(at: backups, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let format = ISO8601DateFormatter()
            format.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let stamp = format.string(from: Date()).replacingOccurrences(of: ":", with: "")
            try original.write(to: backups.appendingPathComponent("claude-settings-\(stamp).json"), options: .withoutOverwriting)
        }
        let temp = settings.deletingLastPathComponent().appendingPathComponent(".pixel-workers-settings-\(getpid()).json")
        try Data(updated.utf8).write(to: temp)
        defer { try? fm.removeItem(at: temp) }
        // Fail closed if something else changed the file meanwhile.
        if (try? Data(contentsOf: settings)) != original { throw InstallError("Claude Code's settings changed while updating them. Nothing was changed; try again.") }
        _ = try fm.replaceItemAt(settings, withItemAt: temp)
        return true
    }

    // JavaScript keeps the settings' key order, which Foundation's JSON parser would not.
    static let script = """
    function transform(text, command, mode, events, notifications, flag) {
      const data = JSON.parse(text)
      if (!data || typeof data !== 'object' || Array.isArray(data)) throw new Error('settings.json is not a JSON object.')
      if (mode === 'normalise') return JSON.stringify(data, null, 2) + '\\n'
      const hooks = data.hooks ?? {}
      if (typeof hooks !== 'object' || Array.isArray(hooks)) throw new Error('settings.json has an unexpected "hooks" value.')
      const ours = h => typeof h?.command === 'string' && h.command.includes(flag)
      if (mode === 'find') {
        for (const groups of Object.values(hooks)) for (const g of Array.isArray(groups) ? groups : []) for (const h of g?.hooks ?? []) if (ours(h)) return h.command
        return ''
      }
      if (mode === 'install' && data.disableAllHooks) throw new Error('Hooks are turned off in Claude Code (disableAllHooks). Nothing was changed.')
      for (const event of new Set([...Object.keys(hooks), ...events])) {
        const groups = (Array.isArray(hooks[event]) ? hooks[event] : [])
          .map(g => Array.isArray(g?.hooks) ? { ...g, hooks: g.hooks.filter(h => !ours(h)) } : g)
          .filter(g => !Array.isArray(g?.hooks) || g.hooks.length)
        if (mode === 'install' && events.includes(event)) {
          const entry = { hooks: [{ type: 'command', command, timeout: 2 }] }
          if (event === 'Notification') entry.matcher = notifications.join('|')
          groups.push(entry)
        }
        if (groups.length) hooks[event] = groups
        else delete hooks[event]
      }
      if (Object.keys(hooks).length) data.hooks = hooks
      else delete data.hooks
      return JSON.stringify(data, null, 2) + '\\n'
    }
    """

    static func transform(_ text: String, command: String?, mode: String) throws -> String {
        guard let context = JSContext() else { throw InstallError("JavaScriptCore is unavailable.") }
        var failure: String?
        context.exceptionHandler = { _, error in failure = error?.toString() }
        context.evaluateScript(script)
        let result = context.objectForKeyedSubscript("transform")
            .call(withArguments: [text, command ?? NSNull(), mode, Hook.events, Hook.notifications, flag])
        if let failure { throw InstallError("Couldn't update Claude Code's settings: \(failure)") }
        guard let output = result?.toString(), result?.isString == true else { throw InstallError("Couldn't update Claude Code's settings.") }
        // Unchanged settings come back byte for byte, so "already installed" is detectable.
        if mode == "install" || mode == "remove", try transform(text, command: nil, mode: "normalise") == output { return text }
        return output
    }
}

public struct InstallError: LocalizedError {
    public let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}
