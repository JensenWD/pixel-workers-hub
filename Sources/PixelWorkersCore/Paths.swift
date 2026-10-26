import Foundation

public enum Paths {
    static let home = FileManager.default.homeDirectoryForCurrentUser

    /// Where the hook keeps one small status file per session. PIXEL_WORKERS_DATA_DIR overrides it (tests, development).
    public static var data: URL {
        if let dir = ProcessInfo.processInfo.environment["PIXEL_WORKERS_DATA_DIR"], !dir.isEmpty { return URL(fileURLWithPath: dir) }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Pixel Workers Hub")
    }
    public static var sessions: URL { data.appendingPathComponent("sessions") }
    public static var backups: URL { data.appendingPathComponent("backups") }

    public static var claudeSettings: URL {
        let dir = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"].map { URL(fileURLWithPath: $0) }
            ?? home.appendingPathComponent(".claude")
        return dir.appendingPathComponent("settings.json")
    }

    /// The `claude` command. Apps opened from Finder don't get your shell's PATH, so the usual install
    /// locations are checked first, then your login shell is asked once. `defaults write
    /// io.github.jensenwd.pixel-workers-hub claudePath /path/to/claude` picks one explicitly.
    public static func claude() -> String? {
        if let saved = UserDefaults.standard.string(forKey: "claudePath"), FileManager.default.isExecutableFile(atPath: saved) { return saved }
        return discovered
    }
    // Looked up once per launch.
    private static let discovered: String? = {
        let candidates = [".local/bin/claude", ".claude/local/claude", ".npm-global/bin/claude", ".bun/bin/claude", ".volta/bin/claude"]
            .map { home.appendingPathComponent($0).path } + ["/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) } ?? fromLoginShell()
    }()

    private static func fromLoginShell() -> String? {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        guard let output = try? Command.run(shell, ["-lic", "command -v claude"], timeout: 5) else { return nil }
        let path = output.split(separator: "\n").last.map { String($0).trimmingCharacters(in: .whitespaces) } ?? ""
        return path.hasPrefix("/") && FileManager.default.isExecutableFile(atPath: path) ? path : nil
    }
}

public struct CommandError: Error, CustomStringConvertible {
    public let status: Int32
    public let stderr: String
    public var description: String { stderr.isEmpty ? "exit status \(status)" : stderr }
}

public enum Command {
    /// Runs a program with arguments (never through a shell) and returns its standard output.
    public static func run(_ path: String, _ arguments: [String], timeout: TimeInterval = 5) throws -> String {
        let process = Process(), out = Pipe(), err = Pipe()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = out
        process.standardError = err
        process.standardInput = FileHandle.nullDevice
        try process.run()
        let timer = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timer)
        // Read both pipes before waiting, so a chatty program can't fill one and stall.
        var output = Data(), errors = Data()
        let group = DispatchGroup()
        group.enter(); DispatchQueue.global().async { errors = err.fileHandleForReading.readDataToEndOfFile(); group.leave() }
        output = out.fileHandleForReading.readDataToEndOfFile()
        group.wait()
        process.waitUntilExit()
        timer.cancel()
        guard process.terminationStatus == 0 else {
            throw CommandError(status: process.terminationStatus, stderr: String(decoding: errors, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return String(decoding: output, as: UTF8.self)
    }
}
