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

    func testAPermissionPromptIsWaitingInClaudeCodesList() {
        // Observed: `claude agents` reports "waiting" while a permission dialog is open.
        let row = LiveSession(sessionId: "s", status: "waiting")
        XCTAssertEqual(Sessions.merge(live: [row], hooks: [:]).first?.status, .needsInput)
    }

    func testHooksSayWhyClaudeStopped() {
        XCTAssertEqual(Sessions.status(.idle, hook(.done)), .yourTurn)
        XCTAssertEqual(Sessions.status(.idle, hook(.failed)), .failed)
        XCTAssertEqual(Sessions.status(.idle, hook(.ready)), .ready)
        XCTAssertEqual(Sessions.status(nil, hook(.needsInput)), .needsInput)
        XCTAssertEqual(Sessions.status(nil, hook(.running)), .working)
    }

    func testClaudeCodesListOverrulesAPromptTheHookMissedTheEndOf() {
        // Approved: the tool runs and Claude is busy until PostToolUse.
        XCTAssertEqual(Sessions.status(.busy, hook(.needsInput)), .working)
        // Dismissed with Esc, which fires no hook.
        XCTAssertEqual(Sessions.status(.idle, hook(.needsInput)), .yourTurn)
    }

    func testAnInterruptedTurnIsYourTurn() {
        // Esc fires no hook, so the hook still says running after Claude went idle.
        XCTAssertEqual(Sessions.status(.idle, hook(.running)), .yourTurn)
        XCTAssertEqual(Sessions.status(.idle, hook(.running, background: 2)), .working)
    }

    func testBusyOverrulesAFinishedHook() {
        XCTAssertEqual(Sessions.status(.busy, hook(.done)), .working)
    }

    func testAHookNewerThanTheListDecides() {
        // Listed idle at t=1000; a permission prompt opened at t=2000.
        let row = LiveSession(sessionId: "s", startedAt: 0, status: "idle")
        XCTAssertEqual(Sessions.merge(live: [row], polledAt: 1000, hooks: ["s": hook(.needsInput)]).first?.status, .needsInput)
        // Listed waiting at t=1000; answered, and the turn finished at t=2000.
        let waiting = LiveSession(sessionId: "s", startedAt: 0, status: "waiting")
        XCTAssertEqual(Sessions.merge(live: [waiting], polledAt: 1000, hooks: ["s": hook(.done)]).first?.status, .yourTurn)
        // Listed idle after the prompt (Esc): the list is newer and decides.
        XCTAssertEqual(Sessions.merge(live: [row], polledAt: 3000, hooks: ["s": hook(.needsInput)]).first?.status, .yourTurn)
    }

    func testAnEmptyNameFallsBackToTheHooksTitle() {
        var titled = hook(.done)
        titled.title = "fix login"
        let merged = Sessions.merge(live: [LiveSession(sessionId: "s", name: "", startedAt: 0, status: "idle")], hooks: ["s": titled])
        XCTAssertEqual(merged.first?.name, "fix login")
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
        let sessions = Sessions.fromHooks(["old": cleared, "new": current, "gone": gone], isAlive: { $0 == 42 }, started: { _ in 50 })
        XCTAssertEqual(sessions.map(\.id), ["new"])
        XCTAssertEqual(sessions.first?.startedAt, 50)
    }

    func testAReusedProcessIdDoesntRaiseAnOldSession() {
        var stale = HookRecord(sessionId: "stale", status: .running, event: "PreToolUse", updatedAt: 100)
        stale.pid = 42
        XCTAssertTrue(Sessions.fromHooks(["stale": stale], isAlive: { _ in true }, started: { _ in 5000 }).isEmpty)
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
        let finished = row?.updatedAt
        Thread.sleep(forTimeInterval: 0.01)
        try send("Notification", ["notification_type": "idle_prompt"])
        XCTAssertEqual(row?.status, .done)
        XCTAssertEqual(row?.updatedAt, finished)
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

    func testLeavesYourOwnOddEntriesAlone() throws {
        let yours = #"{"hooks":{"Stop":[],"PreToolUse":[{"hooks":[]}],"Custom":"keep me"}}"#
        try yours.write(to: settings, atomically: true, encoding: .utf8)
        XCTAssertFalse(try HookInstaller.remove(settings: settings, backups: backups))
        XCTAssertEqual(try String(contentsOf: settings, encoding: .utf8), yours)
        try HookInstaller.install(executable: "/x/PixelWorkersHub", settings: settings, backups: backups)
        try HookInstaller.remove(settings: settings, backups: backups)
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: settings)) as! [String: Any]
        let hooks = json["hooks"] as! [String: Any]
        XCTAssertEqual(hooks["Custom"] as? String, "keep me")
        XCTAssertEqual((hooks["PreToolUse"] as? [Any])?.count, 1)
    }

    func testKeepsItsEntryInPlaceWhenAlreadyInstalled() throws {
        try HookInstaller.install(executable: "/x/PixelWorkersHub", settings: settings, backups: backups)
        var text = try String(contentsOf: settings, encoding: .utf8)
        // Your hook added after ours, in the same event.
        text = text.replacingOccurrences(of: "\"Stop\": [", with: "\"Stop\": [\n{ \"hooks\": [{ \"type\": \"command\", \"command\": \"say hi\" }] },", options: [], range: nil)
        let json = try JSONSerialization.jsonObject(with: Data(text.utf8)) as! [String: Any]
        let reordered = String(decoding: try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted]), as: UTF8.self)
        try reordered.write(to: settings, atomically: true, encoding: .utf8)
        XCTAssertFalse(try HookInstaller.install(executable: "/x/PixelWorkersHub", settings: settings, backups: backups))
    }

    func testFollowsASymlinkedSettingsFile() throws {
        let real = dir.appendingPathComponent("dotfiles/settings.json")
        try FileManager.default.createDirectory(at: real.deletingLastPathComponent(), withIntermediateDirectories: true)
        try existing.write(to: real, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(atPath: settings.path, withDestinationPath: "dotfiles/settings.json")
        XCTAssertTrue(try HookInstaller.install(executable: "/x/PixelWorkersHub", settings: settings, backups: backups))
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: settings.path), "dotfiles/settings.json")
        XCTAssertTrue(try String(contentsOf: real, encoding: .utf8).contains(HookInstaller.flag))
    }

    func testFollowsARelativeLinkInsideALinkedFolder() throws {
        // ~/.claude -> dotfiles/claude, and settings.json -> ../shared/settings.json inside it.
        let fm = FileManager.default
        let home = dir.appendingPathComponent("home"), real = dir.appendingPathComponent("dotfiles/shared/settings.json")
        try fm.createDirectory(at: dir.appendingPathComponent("dotfiles/claude"), withIntermediateDirectories: true)
        try fm.createDirectory(at: real.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.createDirectory(at: home, withIntermediateDirectories: true)
        try existing.write(to: real, atomically: true, encoding: .utf8)
        try fm.createSymbolicLink(atPath: home.appendingPathComponent(".claude").path, withDestinationPath: dir.appendingPathComponent("dotfiles/claude").path)
        try fm.createSymbolicLink(atPath: dir.appendingPathComponent("dotfiles/claude/settings.json").path, withDestinationPath: "../shared/settings.json")
        let link = home.appendingPathComponent(".claude/settings.json")
        XCTAssertTrue(try HookInstaller.install(executable: "/x/PixelWorkersHub", settings: link, backups: backups))
        XCTAssertTrue(try String(contentsOf: real, encoding: .utf8).contains(HookInstaller.flag))
    }

    func testFollowsASymlinkToSettingsNotWrittenYet() throws {
        let real = dir.appendingPathComponent("dotfiles/settings.json")
        try FileManager.default.createDirectory(at: real.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: settings.path, withDestinationPath: "dotfiles/settings.json")
        XCTAssertTrue(try HookInstaller.install(executable: "/x/PixelWorkersHub", settings: settings, backups: backups))
        XCTAssertTrue(try String(contentsOf: real, encoding: .utf8).contains(HookInstaller.flag))
    }

    func testRefusesAnEventItCantAddTo() throws {
        try #"{"hooks":{"Stop":{}}}"#.write(to: settings, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try HookInstaller.install(executable: "/x/PixelWorkersHub", settings: settings, backups: backups))
    }

    func testRefusesUnreadableSettings() throws {
        try existing.write(to: settings, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: settings.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: settings.path) }
        XCTAssertThrowsError(try HookInstaller.install(executable: "/x/PixelWorkersHub", settings: settings, backups: backups))
    }

    func testCreatesSettingsWhenThereAreNone() throws {
        XCTAssertTrue(try HookInstaller.install(executable: "/x/PixelWorkersHub", settings: settings, backups: backups))
        XCTAssertNotNil(HookInstaller.installedExecutable(settings: settings))
    }
}

final class CommandTests: XCTestCase {
    func testReturnsOutput() throws {
        XCTAssertEqual(try Command.run("/bin/echo", ["hi"]), "hi\n")
    }

    func testDoesntWaitOnAChildLeftHoldingTheOutput() throws {
        let start = Date()
        XCTAssertEqual(try Command.run("/bin/sh", ["-c", "sleep 30 & echo hi"], timeout: 5), "hi\n")
        XCTAssertLessThan(Date().timeIntervalSince(start), 5)
    }

    func testStopsAProgramThatIgnoresSigterm() throws {
        let marker = "pwh-sigterm-\(getpid())"
        XCTAssertThrowsError(try Command.run("/bin/sh", ["-c", "trap '' TERM; exec -a \(marker) sleep 30"], timeout: 0.5))
        let left = try? Command.run("/usr/bin/pgrep", ["-f", marker])
        XCTAssertTrue(left?.isEmpty ?? true)
    }

    func testStopsAProgramPastItsTimeout() {
        let start = Date()
        XCTAssertThrowsError(try Command.run("/bin/sleep", ["30"], timeout: 0.5))
        XCTAssertLessThan(Date().timeIntervalSince(start), 5)
    }
}
