import AppKit
import PixelWorkersCore

/// Keeps the session list current. Claude Code's own list (`claude agents --json`) says what's open and
/// whether it's busy; it costs a process launch, so it's polled. The hook's status files are cheap and
/// change the moment something happens, so they're watched and merged in as they land.
final class Store {
    struct Snapshot: Equatable {
        var sessions: [Session] = []
        var error: String?
    }

    /// The latest list, on the main thread.
    private(set) var snapshot = Snapshot()
    var onChange: ((Snapshot) -> Void)?

    // Everything below belongs to `queue`.
    private let queue = DispatchQueue(label: "pixel-workers-hub.store")
    private var live: [LiveSession]?
    /// When `live` was fetched (ms). Hook files written after it are newer news than it is.
    private var livePolledAt: Double = 0
    private var liveError: String?
    private var current = Snapshot()
    private var hosts: [Int32: String] = [:]
    private var watcher: DispatchSourceFileSystemObject?
    private var mergePending = false

    /// full: also ask Claude Code which sessions are open; otherwise only re-read the hook's files.
    func refresh(full: Bool) {
        queue.async { [self] in update(full: full) }
    }

    private func update(full: Bool) {
        if full || live == nil {
            if let claude = Paths.claude() {
                let polled = (Date().timeIntervalSince1970 * 1000).rounded()
                do { live = try Sessions.live(claude: claude); livePolledAt = polled; liveError = nil }
                catch { live = nil; liveError = "Claude Code didn’t list its sessions (\(error)). Try `claude update`." }
            } else {
                live = nil
                liveError = "Couldn’t find the claude command. Point to it with: defaults write io.github.jensenwd.pixel-workers-hub claudePath /path/to/claude"
            }
        }
        // Older Claude Code has no list to ask; the hook's files still know which processes are running.
        var sessions = live.map { Sessions.merge(live: $0, polledAt: livePolledAt, hooks: Hook.records()) } ?? Sessions.fromHooks(Hook.records())
        let pids = Set(sessions.compactMap(\.pid))
        hosts = hosts.filter { pids.contains($0.key) }
        for i in sessions.indices {
            guard let pid = sessions[i].pid else { continue }
            if hosts[pid] == nil { hosts[pid] = Terminals.host(of: pid)?.localizedName ?? "" }
            sessions[i].terminal = hosts[pid].flatMap { $0.isEmpty ? nil : $0 }
        }
        let next = Snapshot(sessions: sessions, error: live == nil && sessions.isEmpty ? liveError : nil)
        guard next != current else { return }
        current = next
        DispatchQueue.main.async { [self] in
            snapshot = next
            onChange?(next)
        }
    }

    /// Re-reads the hook's files whenever one changes, once a burst of writes settles.
    func watchHooks() {
        queue.async { [self] in
            let dir = Paths.sessions
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            Hook.prune(dir)
            let fd = open(dir.path, O_EVTONLY)
            guard fd >= 0 else { return }
            let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: queue)
            source.setEventHandler { [self] in
                guard !mergePending else { return }
                mergePending = true
                queue.asyncAfter(deadline: .now() + 0.15) { [self] in mergePending = false; update(full: false) }
            }
            source.setCancelHandler { close(fd) }
            source.resume()
            watcher?.cancel()
            watcher = source
        }
    }

    /// For the command line: the list as it is right now.
    func load() -> Snapshot {
        queue.sync { update(full: true); return current }
    }

    func focus(_ id: String, done: @escaping (Error?) -> Void) {
        let all = snapshot.sessions
        guard let session = all.first(where: { $0.id == id }) else { return done(Message("That session has ended.")) }
        DispatchQueue.global(qos: .userInitiated).async {
            do { try Terminals.focus(session, among: all); DispatchQueue.main.async { done(nil) } }
            catch { DispatchQueue.main.async { done(error) } }
        }
    }
}

struct Message: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}
