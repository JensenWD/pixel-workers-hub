import Foundation
import XCTest
@testable import PixelWorkersCore

final class StatusTests: XCTestCase {
    func hook(_ status: HookRecord.Status, background: Int = 0) -> HookRecord {
        var row = HookRecord(sessionId: "s", status: status, event: "Stop", updatedAt: 2000)
        row.backgroundCount = background
        return row
    }

    func testClaudeCodesOwnStatusIsEnoughWithoutHooks() {
        XCTAssertEqual(Sessions.status(.busy, nil), .working)
        XCTAssertEqual(Sessions.status(.idle, nil), .yourTurn)
        XCTAssertEqual(Sessions.status(.blocked, nil), .needsInput)
        XCTAssertEqual(Sessions.status(nil, nil), .unknown)
    }

    func testHooksSayWhyClaudeStopped() {
        XCTAssertEqual(Sessions.status(.idle, hook(.done)), .yourTurn)
        XCTAssertEqual(Sessions.status(.idle, hook(.failed)), .failed)
        XCTAssertEqual(Sessions.status(.idle, hook(.ready)), .ready)
        XCTAssertEqual(Sessions.status(.busy, hook(.needsInput)), .needsInput)
        XCTAssertEqual(Sessions.status(nil, hook(.running)), .working)
    }

    func testAnInterruptedTurnIsYourTurn() {
        // Esc fires no hook, so the hook still says running after Claude went idle.
        XCTAssertEqual(Sessions.status(.idle, hook(.running)), .yourTurn)
        XCTAssertEqual(Sessions.status(.idle, hook(.running, background: 2)), .working)
    }

    func testBusyOverrulesAFinishedHook() {
        XCTAssertEqual(Sessions.status(.busy, hook(.done)), .working)
    }

    func testMergeIgnoresHookFilesFromAnEarlierRun() {
        var old = hook(.failed)
        old.updatedAt = 500
        let live = [LiveSession(sessionId: "s", pid: 10, cwd: "/code/app", name: "fix login", startedAt: 1000, status: "idle")]
        let merged = Sessions.merge(live: live, hooks: ["s": old])
        XCTAssertEqual(merged.first?.status, .yourTurn)
        XCTAssertNil(merged.first?.since)
        XCTAssertEqual(merged.first?.project, "app")
    }

    func testMergeKeepsSessionsInTheOrderTheyStarted() {
        let live = [LiveSession(sessionId: "b", startedAt: 20, status: "idle"), LiveSession(sessionId: "a", startedAt: 10, status: "busy"),
                    LiveSession(sessionId: "bg", kind: "background", startedAt: 5)]
        XCTAssertEqual(Sessions.merge(live: live.filter { $0.kind == "interactive" }, hooks: [:]).map(\.id), ["a", "b"])
    }

    func testWithoutTheListOnlyTheLatestSessionOfARunningProcessShows() {
        var cleared = HookRecord(sessionId: "old", status: .done, event: "Stop", updatedAt: 100)
        cleared.pid = 42
        var current = HookRecord(sessionId: "new", status: .ready, event: "SessionStart", updatedAt: 200)
        current.pid = 42
        var gone = HookRecord(sessionId: "gone", status: .done, event: "Stop", updatedAt: 300)
        gone.pid = 43
        let sessions = Sessions.combine(live: [], hooks: ["old": cleared, "new": current, "gone": gone], isAlive: { $0 == 42 }, started: { _ in 50 })
        XCTAssertEqual(sessions.map(\.id), ["new"])
        XCTAssertEqual(sessions.first?.startedAt, 50)
    }

    func testANewSessionShowsBeforeClaudeCodeListsIt() {
        var fresh = HookRecord(sessionId: "fresh", status: .needsInput, event: "Notification", updatedAt: 300)
        fresh.pid = 7
        var cleared = HookRecord(sessionId: "before-clear", status: .done, event: "Stop", updatedAt: 100)
        cleared.pid = 8
        let live = [LiveSession(sessionId: "listed", pid: 8, startedAt: 10, status: "idle")]
        let sessions = Sessions.combine(live: live, hooks: ["fresh": fresh, "before-clear": cleared], isAlive: { _ in true }, started: { _ in 20 })
        XCTAssertEqual(sessions.map(\.id), ["listed", "fresh"])
        XCTAssertEqual(sessions.last?.status, .needsInput)
    }
}

final class GhosttyTests: XCTestCase {
    func session(_ id: String, _ name: String, _ cwd: String = "/code/app") -> Session {
        Session(id: id, pid: 1, name: name, cwd: cwd, project: "app", startedAt: 0, status: .working)
    }

    func testFindsTheTabTitledWithTheSessionName() {
        let tabs = [Terminals.GhosttyTab(id: "1", title: "zsh", dir: "/code/app"),
                    Terminals.GhosttyTab(id: "2", title: "✳ Fix Login", dir: "/code/app")]
        XCTAssertEqual(Terminals.pick(tabs, for: session("s", "fix login"), among: [])?.id, "2")
    }

    func testPrefersTheSessionsFolderWhenTwoTabsShareAName() {
        let tabs = [Terminals.GhosttyTab(id: "1", title: "◐ tests", dir: "/code/other"),
                    Terminals.GhosttyTab(id: "2", title: "✳ tests", dir: "/code/app")]
        XCTAssertEqual(Terminals.pick(tabs, for: session("s", "tests"), among: [])?.id, "2")
    }

    func testFallsBackToTheOneClaudeTabInTheFolder() {
        let tabs = [Terminals.GhosttyTab(id: "1", title: "✳ Claude Code", dir: "/code/app"),
                    Terminals.GhosttyTab(id: "2", title: "~/code/app", dir: "/code/app"),
                    Terminals.GhosttyTab(id: "3", title: "✳ other work", dir: "/code/app")]
        let me = session("s", "renamed since"), other = session("o", "other work")
        XCTAssertEqual(Terminals.pick(tabs, for: me, among: [me, other])?.id, "1")
    }

    func testRefusesToGuessBetweenTwoUnnamedTabs() {
        let tabs = [Terminals.GhosttyTab(id: "1", title: "✳ Claude Code", dir: "/code/app"),
                    Terminals.GhosttyTab(id: "2", title: "✳ Claude Code", dir: "/code/app")]
        XCTAssertNil(Terminals.pick(tabs, for: session("s", ""), among: []))
    }
}

final class HookTests: XCTestCase {
    var dir: URL!
    override func setUp() {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("pwh-tests-\(UUID().uuidString)")
    }
    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    func send(_ event: String, _ extra: [String: Any] = [:]) throws {
        try Hook.record(["hook_event_name": event, "session_id": "abc-123", "cwd": "/code/app", "prompt": "secret"].merging(extra) { $1 },
                        in: dir, claudePid: 77)
    }
    var row: HookRecord? { Hook.records(in: dir)["abc-123"] }

    func testFollowsASessionThroughATurn() throws {
        try send("SessionStart")
        XCTAssertEqual(row?.status, .ready)
        try send("UserPromptSubmit")
        XCTAssertEqual(row?.status, .running)
        try send("Notification", ["notification_type": "permission_prompt"])
        XCTAssertEqual(row?.status, .needsInput)
        try send("PostToolUse")
        XCTAssertEqual(row?.status, .running)
        try send("Stop", ["background_tasks": []])
        XCTAssertEqual(row?.status, .done)
        try send("Notification", ["notification_type": "idle_prompt"])
        XCTAssertEqual(row?.status, .done)
        try send("Stop", ["background_tasks": [["id": "1"]]])
        XCTAssertEqual(row?.status, .running)
        XCTAssertEqual(row?.backgroundCount, 1)
        try send("SessionEnd")
        XCTAssertEqual(row?.status, .ended)
        XCTAssertEqual(row?.pid, 77)
        XCTAssertEqual(row?.cwd, "/code/app")
    }

    func testKeepsOnlyMetadata() throws {
        try send("UserPromptSubmit", ["session_title": "fix\u{7}login"])
        let text = try String(contentsOf: dir.appendingPathComponent("abc-123.json"), encoding: .utf8)
        XCTAssertFalse(text.contains("secret"))
        XCTAssertEqual(row?.title, "fixlogin")
    }

    func testIgnoresSubagentsUnknownEventsAndBadIds() throws {
        try send("PreToolUse", ["agent_id": "sub"])
        try send("Elsewhere")
        try send("Notification", ["notification_type": "auth_success"])
        try Hook.record(["hook_event_name": "Stop", "session_id": "../escape"], in: dir, claudePid: nil)
        XCTAssertTrue(Hook.records(in: dir).isEmpty)
    }

    func testPrunesSessionsSilentForAWeek() throws {
        try send("Stop")
        Hook.prune(dir, now: Date().addingTimeInterval(8 * 86_400))
        XCTAssertNil(row)
    }
}

final class InstallerTests: XCTestCase {
    var dir: URL!
    var settings: URL { dir.appendingPathComponent("settings.json") }
    var backups: URL { dir.appendingPathComponent("backups") }
    override func setUp() {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("pwh-install-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    let existing = """
    {
      "theme": "dark",
      "hooks": {
        "Stop": [{ "hooks": [{ "type": "command", "command": "say done" }] }]
      },
      "model": "opus"
    }
    """

    func testAddsItsHooksBesideYoursAndKeepsYourSettingsInOrder() throws {
        try existing.write(to: settings, atomically: true, encoding: .utf8)
        XCTAssertTrue(try HookInstaller.install(executable: "/Applications/Pixel Workers Hub.app/Contents/MacOS/PixelWorkersHub", settings: settings, backups: backups))
        let text = try String(contentsOf: settings, encoding: .utf8)
        XCTAssertLessThan(text.range(of: "theme")!.lowerBound, text.range(of: "model")!.lowerBound)
        XCTAssertTrue(text.contains("say done"))
        let json = try JSONSerialization.jsonObject(with: Data(text.utf8)) as! [String: Any]
        let hooks = json["hooks"] as! [String: [[String: Any]]]
        XCTAssertEqual(Set(hooks.keys), Set(Hook.events))
        XCTAssertEqual(hooks["Stop"]?.count, 2)
        XCTAssertEqual(hooks["Notification"]?.first?["matcher"] as? String, Hook.notifications.joined(separator: "|"))
        XCTAssertEqual(HookInstaller.installedExecutable(settings: settings), "/Applications/Pixel Workers Hub.app/Contents/MacOS/PixelWorkersHub")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: backups.path).count, 1)
    }

    func testInstallingTwiceChangesNothing() throws {
        try existing.write(to: settings, atomically: true, encoding: .utf8)
        try HookInstaller.install(executable: "/x/PixelWorkersHub", settings: settings, backups: backups)
        XCTAssertFalse(try HookInstaller.install(executable: "/x/PixelWorkersHub", settings: settings, backups: backups))
    }

    func testAMovedAppReplacesItsOldHooks() throws {
        try HookInstaller.install(executable: "/old/PixelWorkersHub", settings: settings, backups: backups)
        try HookInstaller.install(executable: "/new/it's here/PixelWorkersHub", settings: settings, backups: backups)
        let text = try String(contentsOf: settings, encoding: .utf8)
        XCTAssertFalse(text.contains("/old/"))
        XCTAssertEqual(HookInstaller.installedExecutable(settings: settings), "/new/it's here/PixelWorkersHub")
    }

    func testRemovingLeavesOnlyYourSettings() throws {
        try existing.write(to: settings, atomically: true, encoding: .utf8)
        try HookInstaller.install(executable: "/x/PixelWorkersHub", settings: settings, backups: backups)
        XCTAssertTrue(try HookInstaller.remove(settings: settings, backups: backups))
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: settings)) as! [String: Any]
        let hooks = json["hooks"] as! [String: Any]
        XCTAssertEqual(Array(hooks.keys), ["Stop"])
        XCTAssertNil(HookInstaller.installedExecutable(settings: settings))
    }

    func testRefusesBrokenSettingsAndLeavesThemAlone() throws {
        try "{ not json".write(to: settings, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try HookInstaller.install(executable: "/x/PixelWorkersHub", settings: settings, backups: backups))
        XCTAssertEqual(try String(contentsOf: settings, encoding: .utf8), "{ not json")
    }

    func testRespectsHooksBeingTurnedOff() throws {
        try #"{"disableAllHooks": true}"#.write(to: settings, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try HookInstaller.install(executable: "/x/PixelWorkersHub", settings: settings, backups: backups))
    }

    func testCreatesSettingsWhenThereAreNone() throws {
        XCTAssertTrue(try HookInstaller.install(executable: "/x/PixelWorkersHub", settings: settings, backups: backups))
        XCTAssertNotNil(HookInstaller.installedExecutable(settings: settings))
    }
}
