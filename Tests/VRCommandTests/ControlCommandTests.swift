import Foundation
import Testing
@testable import VRCommand
import VRLease
import VRWire

private let table = CommandTable.standard

/// `video-review control take [--wait <seconds>] | release` as an agent
/// runs it, with an in-memory app at the end of the socket: what each
/// command sends, with which timeout, prints and exits with. The lease's
/// rules are the app's, in `ControlLeaseTests`.
@Suite struct ControlCommandTests {
    @Test(arguments: [
        (["take"], ControlRequest.controlTake(waitSeconds: nil), 15.0),
        (["take", "--wait", "30"], .controlTake(waitSeconds: 30), 45),
        (["take", "--wait", "0"], .controlTake(waitSeconds: 0), 15),
        (["release"], .controlRelease, 15),
    ])
    func takeAndReleaseEachSendOneRequestAndATakeThatWaitsReadsItsReplyForTheWaitLonger(
        arguments: [String], request: ControlRequest, timeout: TimeInterval
    ) throws {
        let app = try FakeApp()
        app.start(in: app.support)
        app.answer = { _ in .done("done\n") }

        let result = table.run(["control"] + arguments, environment: app.environment)

        #expect(result == CommandResult(output: "done\n"))
        #expect(app.requests == [request])
        #expect(app.timeouts == [timeout])
    }

    @Test func theAppsAnswerPrintsAsItIsHeldReleasedOrRefusedWithExitOne() throws {
        let app = try FakeApp()
        app.start(in: app.support)

        app.answer = { _ in .done("you hold video-review until 12:05:00\n") }
        #expect(table.run(["control", "take"], environment: app.environment)
            == CommandResult(output: "you hold video-review until 12:05:00\n"))

        app.answer = { _ in .done(#"{"held":true,"until":"2026-10-04T12:05:00Z"}"# + "\n") }
        #expect(table.run(["control", "take", "--json"], environment: app.environment)
            == CommandResult(output: #"{"held":true,"until":"2026-10-04T12:05:00Z"}"# + "\n"))
        #expect(app.messages.last?.json == true)

        let inUse = "video-review is in use by codex in Herdr pane w1-2 until 12:05:00 (40s left); "
            + "`video-review control take --wait <seconds>` to queue"
        app.answer = { _ in .refused(inUse) }
        #expect(table.run(["control", "take"], environment: app.environment) == CommandResult(error: inUse + "\n", status: 1))

        app.timesOut = true
        #expect(table.run(["control", "take", "--wait", "30"], environment: app.environment)
            == CommandResult(error: "video-review didn't answer within 45 seconds\n", status: 1))
    }

    @Test func controlToAnAppThatIsNotRunningExitsOne() throws {
        let app = try FakeApp()
        #expect(table.run(["control", "release"], environment: app.environment)
            == CommandResult(error: "video-review isn't running; `video-review app open`\n", status: 1))
    }

    @Test(arguments: [
        (["control"], ""),
        (["control", "hold"], "video-review control: unknown command `hold`\n"),
        (["control", "take", "now"], "video-review control take: unexpected `now`\n"),
        (["control", "take", "--wait"], "video-review control take: --wait needs a number of seconds\n"),
        (["control", "take", "--wait", "soon"], "video-review control take: --wait takes whole seconds from 0 to 3600, not `soon`\n"),
        (["control", "take", "--wait", "-5"], "video-review control take: --wait takes whole seconds from 0 to 3600, not `-5`\n"),
        (["control", "take", "--wait", "1.5"], "video-review control take: --wait takes whole seconds from 0 to 3600, not `1.5`\n"),
        (["control", "take", "--wait", "3601"], "video-review control take: --wait takes whole seconds from 0 to 3600, not `3601`\n"),
        (["control", "take", "--wait", "5", "--wait", "6"], "video-review control take: unexpected `--wait`\n"),
        (["control", "release", "--wait", "5"], "video-review control release: unexpected `--wait`\n"),
        (["control", "release", "now"], "video-review control release: unexpected `now`\n"),
    ])
    func argumentsThatDoNotReadExitTwoWithTheControlUsageAndSendNothing(arguments: [String], line: String) throws {
        let app = try FakeApp()
        app.start(in: app.support)

        let result = table.run(arguments, environment: app.environment)

        #expect(result == CommandResult(error: line + ControlCommand.usageText, status: 2))
        #expect(app.requests.isEmpty)
    }

    @Test func controlHelpPrintsTheControlUsageAndTheTopLevelHelpListsControl() throws {
        let app = try FakeApp()
        #expect(table.run(["control", "--help"], environment: app.environment) == CommandResult(output: ControlCommand.usageText))
        #expect(table.run(["control", "take", "-h"], environment: app.environment) == CommandResult(output: ControlCommand.usageText))
        #expect(table.run(["--help"], environment: app.environment).output.contains("  control "))
        #expect(app.requests.isEmpty)
    }

    @Test func everyCommandIsSentAsTheHolderTheEnvironmentNames() throws {
        let app = try FakeApp()
        app.start(in: app.support)
        let holders = Holders()
        app.answer = { message in
            holders.add(message.holder)
            return .done("")
        }
        var environment = app.environment

        _ = table.run(["control", "take"], environment: environment)
        environment.variables[Holder.keyVariable] = "run-7"
        _ = table.run(["player", "play"], environment: environment)

        #expect(holders.all == [
            Holder(key: "CLAUDE_CODE_SESSION_ID=test", name: "Claude Code", place: "/Users/me/repo"),
            Holder(key: "run-7", name: "Claude Code", place: "/Users/me/repo"),
        ])
    }
}

/// The holders the fake app saw, in order.
private final class Holders: @unchecked Sendable {
    private let lock = NSLock()
    private var seen: [Holder] = []

    func add(_ holder: Holder) { lock.withLock { seen.append(holder) } }
    var all: [Holder] { lock.withLock { seen } }
}

/// A relaunch hands the quit app's lease to the launched one.
@Suite struct LeaseHandoverTests {
    private let fixture = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("fixtures/sample", isDirectory: true)
        .standardizedFileURL
    private static let term = ControlLease.Term(
        holder: Holder(key: "CLAUDE_CODE_SESSION_ID=test", name: "Claude Code", place: "/Users/me/repo"),
        taken: Date(timeIntervalSince1970: 0), ends: Date(timeIntervalSince1970: 70.5)
    )
    private static let handed = #"{"ends":70.5,"holder":{"key":"CLAUDE_CODE_SESSION_ID=test","name":"Claude Code","place":"/Users/me/repo"},"taken":0}"#

    @Test func openDemoHandsTheQuitAppsLeaseToTheDemo() throws {
        let app = try FakeApp()
        app.start(in: app.support)
        app.answer = { $0.request == .appQuit ? ControlReply(ok: true, output: "video-review quit\n", lease: Self.term) : .done("") }

        let result = table.run(["app", "open", "--demo", fixture.path], environment: app.environment)

        #expect(result.status == 0)
        #expect(app.launches.first?.environment == [
            "VIDEO_REVIEW_SUPPORT_DIR": DemoPointer.supportFolder(forDemo: fixture, in: app.support).path,
            "VIDEO_REVIEW_DEMO_DIR": fixture.path,
            "VIDEO_REVIEW_CONTROL_LEASE": Self.handed,
        ])
    }

    @Test func plainOpenAfterADemoHandsTheDemosLeaseToTheNormalApp() throws {
        let app = try FakeApp()
        _ = table.run(["app", "open", "--demo", fixture.path], environment: app.environment)
        app.answer = { $0.request == .appQuit ? ControlReply(ok: true, output: "video-review quit\n", lease: Self.term) : .done("") }

        let result = table.run(["app", "open"], environment: app.environment)

        #expect(result.status == 0)
        #expect(app.launches.last?.environment == ["VIDEO_REVIEW_CONTROL_LEASE": Self.handed])
    }

    @Test func aQuitThatHandsNoLeaseBackLaunchesWithNone() throws {
        let app = try FakeApp()
        app.start(in: app.support)

        _ = table.run(["app", "open", "--demo", fixture.path], environment: app.environment)

        #expect(app.launches.first?.environment[ControlLease.handoverVariable] == nil)
    }
}
