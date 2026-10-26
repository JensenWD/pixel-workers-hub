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

    static func update(settings link: URL, backups: URL, command: String?, mode: String) throws -> Bool {
        let fm = FileManager.default
        // A settings.json linked in from a dotfiles repo is updated where it really lives.
        let settings = resolve(link)
        // Missing means "no settings yet"; unreadable is an error, never a reason to start from scratch.
        let original = fm.fileExists(atPath: settings.path) ? try Data(contentsOf: settings) : nil
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
        let now = fm.fileExists(atPath: settings.path) ? try Data(contentsOf: settings) : nil
        if now != original { throw InstallError("Claude Code's settings changed while updating them. Nothing was changed; try again.") }
        if original == nil { try fm.moveItem(at: temp, to: settings) }
        else { _ = try fm.replaceItemAt(settings, withItemAt: temp) }
        return true
    }

    /// Follows symlinks, including one to a file that doesn't exist yet.
    static func resolve(_ url: URL) -> URL {
        var current = url.standardizedFileURL
        for _ in 0..<16 {
            guard let target = try? FileManager.default.destinationOfSymbolicLink(atPath: current.path) else { return current }
            current = URL(fileURLWithPath: target, relativeTo: current.deletingLastPathComponent()).standardizedFileURL
        }
        return current
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
      const entry = event => Object.assign({ hooks: [{ type: 'command', command, timeout: 2 }] }, event === 'Notification' ? { matcher: notifications.join('|') } : {})
      const had = data.hooks !== undefined, before = Object.keys(hooks).length
      for (const event of new Set([...Object.keys(hooks), ...events])) {
        const want = mode === 'install' && events.includes(event)
        // Anything that isn't a list of hook groups isn't ours to touch.
        if (hooks[event] !== undefined && !Array.isArray(hooks[event])) {
          if (want) throw new Error(`settings.json has an unexpected "${event}" hook value. Nothing was changed.`)
          continue
        }
        const groups = []
        let present = false
        for (const g of hooks[event] ?? []) {
          // An entry that's already exactly right stays where it is.
          if (want && !present && JSON.stringify(g) === JSON.stringify(entry(event))) { groups.push(g); present = true; continue }
          if (!Array.isArray(g?.hooks) || !g.hooks.some(ours)) { groups.push(g); continue }
          const rest = g.hooks.filter(h => !ours(h))
          if (rest.length) groups.push({ ...g, hooks: rest })
        }
        if (want && !present) groups.push(entry(event))
        if (groups.length) hooks[event] = groups
        // Only a list this emptied goes; one that was already empty is yours.
        else if (hooks[event]?.length) delete hooks[event]
      }
      if (Object.keys(hooks).length || had && !before) data.hooks = hooks
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
