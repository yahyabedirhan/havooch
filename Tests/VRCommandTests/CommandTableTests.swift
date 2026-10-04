import Foundation
import Testing
@testable import VRCommand
import VRLease
import VRWire

@Suite struct CommandTableTests {
    let harness = CommandHarness()

    /// The one request `line` sends to an app that answers `done`.
    private func request(_ line: String...) -> ControlRequest? {
        let transport = FakeTransport(reply: .done("ok\n"))
        #expect(harness.run(line: line, transport: transport) == CommandResult(output: "ok\n"))
        #expect(transport.requests.count == 1)
        return transport.requests.first
    }

    @Test func eachCommandLineBecomesItsRequest() {
        #expect(request("state", "--json") == .state)
        #expect(request("state") == .state)
        #expect(request("player", "play") == .playerPlay)
        #expect(request("player", "pause") == .playerPause)
        #expect(request("player", "seek", "0:10") == .playerSeek(seconds: 10))
        #expect(request("player", "seek", "12.5") == .playerSeek(seconds: 12.5))
        #expect(request("player", "open", "/videos/sample.mp4") == .playerOpen(path: "/videos/sample.mp4"))
        #expect(request("screenshot", "/tmp/window.png") == .screenshot(path: "/tmp/window.png", appearance: nil))
        #expect(request("screenshot", "/tmp/window.png", "--appearance", "dark") == .screenshot(path: "/tmp/window.png", appearance: .dark))
        #expect(request("screenshot", "--appearance", "light", "/tmp/window.png") == .screenshot(path: "/tmp/window.png", appearance: .light))
    }

    @Test func takeAndReleaseBecomeTheirRequests() {
        #expect(request("control", "take") == .controlTake(waitSeconds: nil))
        #expect(request("control", "take", "--wait", "30") == .controlTake(waitSeconds: 30))
        #expect(request("control", "take", "--wait", "0") == .controlTake(waitSeconds: 0))
        #expect(request("control", "take", "--wait", "3600") == .controlTake(waitSeconds: 3600))
        #expect(request("control", "release") == .controlRelease)
    }

    @Test func aTakeThatWaitsInLineIsGivenItsWaitOnTopOfTheUsualSilence() {
        let transport = FakeTransport(reply: .done("you hold video-review until 12:05:00\n"))
        _ = harness.run("control", "take", transport: transport)
        _ = harness.run("control", "take", "--wait", "120", transport: transport)
        _ = harness.run("control", "release", transport: transport)
        #expect(transport.exchanges.current.map(\.idleTimeout) == [15, 135, 15])
    }

    @Test func aCommandRefusedTheLeaseExitsOneWithTheHolderAndTheEndOfTheLease() {
        let refusal = "video-review is in use by Claude Code in /work until 12:01:00 (48s left); "
            + "`video-review control take --wait <seconds>` to queue"
        for line in [["player", "play"], ["control", "take"], ["screenshot", "/tmp/w.png"]] {
            let refused = harness.run(line: line, transport: FakeTransport(reply: .refused(refusal)))
            #expect(refused == CommandResult(error: refusal + "\n", exitCode: 1))
        }
    }

    @Test func aRelativeVideoPathIsTakenAgainstTheWorkingFolder() {
        #expect(request("player", "open", "fixtures/sample.mp4") == .playerOpen(path: "/work/fixtures/sample.mp4"))
        #expect(request("player", "open", "../sample.mp4") == .playerOpen(path: "/sample.mp4"))
    }

    @Test func jsonIsAcceptedAnywhereOnTheLineAndTravelsWithTheRequest() {
        for line in [["--json", "player", "seek", "10"], ["player", "--json", "seek", "10"], ["player", "seek", "10", "--json"]] {
            let transport = FakeTransport(reply: .done("{}\n"))
            _ = harness.run(line: line, transport: transport)
            #expect(transport.exchanges.current.map(\.message.json) == [true])
            #expect(transport.requests == [.playerSeek(seconds: 10)])
        }
        let plain = FakeTransport(reply: .done("0:10.000\n"))
        _ = harness.run("player", "seek", "10", transport: plain)
        #expect(plain.exchanges.current.map(\.message.json) == [false])
    }

    @Test func everyRequestCarriesTheHolderTheCommandFound() {
        let transport = FakeTransport(reply: .done(""))
        _ = harness.run("player", "play", transport: transport)
        _ = harness.run("player", "play", variables: ["CLAUDE_CODE_SESSION_ID": "abc", "HERDR_PANE_ID": "w1:p2"], transport: transport)
        _ = harness.run("player", "play", variables: ["CLAUDE_CODE_SESSION_ID": "abc", "VIDEO_REVIEW_CONTROL_KEY": "second agent"], transport: transport)
        #expect(transport.exchanges.current.map(\.message.holder) == [
            Holder(key: "process:300@800250000", name: "claude", place: "/work"),
            Holder(key: "CLAUDE_CODE_SESSION_ID=abc", name: "Claude Code", place: "Herdr pane w1:p2"),
            Holder(key: "second agent", name: "Claude Code", place: "/work"),
        ])
    }

    @Test(arguments: [
        (["player", "seek"], "player seek: missing <seconds|mm:ss>", "player seek <seconds|mm:ss>"),
        (["player", "seek", "soon"], "player seek: `soon` isn't a time; write seconds (10, 10.5) or mm:ss (0:10)", "player seek <seconds|mm:ss>"),
        (["player", "seek", "10", "20"], "player seek: unexpected `20`", "player seek <seconds|mm:ss>"),
        (["player", "play", "--fast"], "player play: unknown option `--fast`", "player play"),
        (["player", "open"], "player open: missing <path>", "player open <path>"),
        (["screenshot", "window.png"], "screenshot: `window.png` isn't an absolute path", "screenshot <abs.png> [--appearance light|dark]"),
        (
            ["screenshot", "/tmp/w.png", "--appearance", "sepia"],
            "screenshot: no appearance `sepia`; it takes `light` or `dark`", "screenshot <abs.png> [--appearance light|dark]"
        ),
        (["screenshot", "/tmp/w.png", "--appearance"], "screenshot: --appearance needs a value", "screenshot <abs.png> [--appearance light|dark]"),
        (["app", "open", "--demo"], "app open: --demo needs a value", "app open [--demo <folder>]"),
        (["control", "take", "--wait"], "control take: --wait needs a value", "control take [--wait <s>]"),
        (["control", "take", "--wait", "soon"], "control take: --wait takes whole seconds from 0 to 3600, not `soon`", "control take [--wait <s>]"),
        (["control", "take", "--wait", "3601"], "control take: --wait takes whole seconds from 0 to 3600, not `3601`", "control take [--wait <s>]"),
        (["control", "take", "--wait", "-1"], "control take: --wait takes whole seconds from 0 to 3600, not `-1`", "control take [--wait <s>]"),
        (["control", "take", "30"], "control take: unexpected `30`", "control take [--wait <s>]"),
        (["control", "release", "--wait", "5"], "control release: unknown option `--wait`", "control release"),
        (["app", "quit", "now"], "app quit: unexpected `now`", "app quit"),
    ])
    func aLineThatDoesNotParseExitsTwoWithItsUsageAndSendsNothing(line: [String], error: String, usage: String) {
        let transport = FakeTransport(reply: .done(""))
        let result = harness.run(line: line, transport: transport)
        #expect(result == CommandResult(error: "video-review \(error)\nusage: video-review \(usage)\n", exitCode: 2))
        #expect(transport.requests.isEmpty)
        #expect(harness.launcher.launches.current.isEmpty)
    }

    @Test func anUnknownCommandExitsTwoWithTheWholeTable() {
        let transport = FakeTransport(reply: .done(""))
        for (line, named) in [(["player", "rewind"], "player rewind"), (["dance"], "dance"), (["player"], "player")] {
            let result = harness.run(line: line, transport: transport)
            #expect(result.exitCode == 2)
            #expect(result.output.isEmpty)
            #expect(result.error.hasPrefix("video-review: unknown command `\(named)`\nusage: video-review <command> [--json]\n"))
        }
        #expect(transport.requests.isEmpty)
    }

    @Test func helpListsEveryCommand() {
        let transport = FakeTransport(reply: .done(""))
        let help = harness.run("help", transport: transport)
        #expect(help.exitCode == 0)
        for command in CommandTable.all {
            #expect(help.output.contains("video-review \(command.usage)"))
        }
        #expect(harness.run("player", "seek", "--help", transport: transport) == help)
        #expect(harness.run(line: [], transport: transport) == CommandResult(error: help.output, exitCode: 2))
        #expect(transport.requests.isEmpty)
    }

    @Test func aRefusalIsOneLineOnStandardErrorAndExitOne() {
        let refused = harness.run("player", "play", transport: FakeTransport(reply: .refused("no video is open")))
        #expect(refused == CommandResult(error: "no video is open\n", exitCode: 1))
    }

    @Test func aNoteBesideTheOutputGoesToStandardError() {
        let noted = harness.run(
            "screenshot", "/tmp/w.png", transport: FakeTransport(reply: .done("/tmp/w.png\n", note: "rendered, not captured\n"))
        )
        #expect(noted == CommandResult(output: "/tmp/w.png\n", error: "rendered, not captured\n"))
    }

    @Test func aCommandForAnAppThatIsNotRunningExitsOne() {
        let result = harness.run("player", "play", transport: .nothingListens)
        #expect(result == CommandResult(error: "video-review isn't running; `video-review app open`\n", exitCode: 1))
        let silent = harness.run("player", "play", transport: FakeTransport { _, _ in .failure(.timedOut) })
        #expect(silent == CommandResult(error: "video-review didn't answer within 15 seconds\n", exitCode: 1))
    }

    @Test func theCommandFindsTheBundleItSitsIn() {
        let inside = URL(fileURLWithPath: "/Applications/Video Review (proto-1).app/Contents/Helpers/video-review")
        #expect(CommandEnvironment.enclosingBundle(of: inside)?.path == "/Applications/Video Review (proto-1).app")
        #expect(CommandEnvironment.enclosingBundle(of: URL(fileURLWithPath: "/repo/.build/release/video-review-cli")) == nil)
        #expect(CommandEnvironment.enclosingBundle(of: URL(fileURLWithPath: "/usr/local/Helpers/video-review")) == nil)
        #expect(CommandEnvironment.enclosingBundle(of: nil) == nil)
    }
}
