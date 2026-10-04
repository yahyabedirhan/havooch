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

    @Test func aRequestThatWaitsAcceptsNoLongerSilenceSinceTheAppsHeartbeatBreaksIt() {
        let transport = FakeTransport(reply: .done("you hold video-review until 12:05:00\n"))
        _ = harness.run("control", "take", transport: transport)
        _ = harness.run("control", "take", "--wait", "120", transport: transport)
        _ = harness.run("wait", transport: transport)
        _ = harness.run("wait", "--timeout", "600", transport: transport)
        #expect(transport.exchanges.current.map(\.idleTimeout) == [15, 15, 15, 15])
    }

    // MARK: - Sending and listening

    @Test func sendAndWaitBecomeTheirRequests() {
        #expect(request("batch", "send") == .batchSend)
        #expect(request("wait") == .wait(timeoutSeconds: nil))
        #expect(request("wait", "--timeout", "30") == .wait(timeoutSeconds: 30))
        #expect(request("wait", "--timeout", "0") == .wait(timeoutSeconds: 0))
        #expect(request("wait", "--json") == .wait(timeoutSeconds: nil))
    }

    @Test func contextSetBecomesItsRequestWithTheTextAsItWasTyped() {
        #expect(request("context", "set", "the lease walk, from shipyard") == .contextSet(text: "the lease walk, from shipyard"))
        // An empty text clears the note.
        #expect(request("context", "set", "") == .contextSet(text: ""))
    }

    @Test func aWaitPrintsTheBatchAsTheAppBuiltItAndExitsZero() {
        let payload = #"{"batch":{"id":"7f3a9c21-b1","sentAt":"2026-10-04T12:00:00Z"},"comments":[],"context":null}"# + "\n"

        let result = harness.run("wait", "--timeout", "30", transport: FakeTransport(reply: .done(payload)))

        #expect(result == CommandResult(output: payload))
    }

    @Test func aWaitWhoseTimeoutRanOutExitsThreeAndPrintsNothingOnStandardOutput() {
        // The app answers a wait that ran out with nothing to print.
        let ranOut = FakeTransport(reply: .done(""))

        #expect(harness.run("wait", "--timeout", "30", transport: ranOut) == CommandResult(error: "no batch within 30 s\n", exitCode: 3))
        #expect(harness.run("wait", "--timeout", "0", "--json", transport: ranOut) == CommandResult(error: "no batch within 0 s\n", exitCode: 3))
        // Only a wait: another command with nothing to print is done.
        #expect(harness.run("player", "play", transport: ranOut) == CommandResult())
    }

    @Test func aWaitThatIsRefusedExitsOne() {
        let refusal = "Claude Code in /work is already listening; one listener at a time"

        let refused = harness.run("wait", transport: FakeTransport(reply: .refused(refusal)))

        #expect(refused == CommandResult(error: refusal + "\n", exitCode: 1))
    }

    // MARK: - Answering

    @Test func eachAnswerLineBecomesItsRequest() {
        #expect(request("ack", "7f3a9c21-b1") == .ack(id: "7f3a9c21-b1", text: nil))
        #expect(request("ack", "7f3a9c21-b1", "got it") == .ack(id: "7f3a9c21-b1", text: "got it"))
        #expect(request("status", "7f3a9c21-c1", "working") == .status(id: "7f3a9c21-c1", state: "working"))
        #expect(request("status", "7f3a9c21-c1", "done") == .status(id: "7f3a9c21-c1", state: "done"))
        #expect(request("status", "7f3a9c21-c1", "failed") == .status(id: "7f3a9c21-c1", state: "failed"))
        #expect(request("reply", "7f3a9c21-c1", "fixed in a1b2c3") == .reply(id: "7f3a9c21-c1", text: "fixed in a1b2c3"))
        #expect(request("reply", "7f3a9c21-b1", "both are in") == .reply(id: "7f3a9c21-b1", text: "both are in"))
        #expect(request("ask", "7f3a9c21-c1", "which one?") == .ask(id: "7f3a9c21-c1", text: "which one?", waitSeconds: nil))
        #expect(request("ask", "7f3a9c21-c1", "which one?", "--wait", "60") == .ask(id: "7f3a9c21-c1", text: "which one?", waitSeconds: 60))
        #expect(request("ask", "--wait", "0", "7f3a9c21-c1", "which one?") == .ask(id: "7f3a9c21-c1", text: "which one?", waitSeconds: 0))
        #expect(request("thread", "answer", "7f3a9c21-c1", "the left one") == .threadAnswer(id: "7f3a9c21-c1", text: "the left one"))
    }

    @Test func anAskPrintsTheAnswerAndExitsZero() {
        let result = harness.run("ask", "7f3a9c21-c1", "which one?", "--wait", "60", transport: FakeTransport(reply: .done("the left one\n")))

        #expect(result == CommandResult(output: "the left one\n"))
    }

    @Test func anAskWhoseWaitRanOutExitsThreeAndPrintsNothingOnStandardOutput() {
        // The app answers an ask that ran out with nothing to print.
        let ranOut = FakeTransport(reply: .done(""))

        #expect(harness.run("ask", "7f3a9c21-c1", "which one?", "--wait", "60", transport: ranOut)
            == CommandResult(error: "no answer within 60 s\n", exitCode: 3))
        #expect(harness.run("ask", "7f3a9c21-c1", "which one?", "--wait", "0", "--json", transport: ranOut)
            == CommandResult(error: "no answer within 0 s\n", exitCode: 3))
    }

    @Test func anAskKeepsTheUsualIdleTimeoutSinceTheAppsHeartbeatBreaksTheSilence() {
        let transport = FakeTransport(reply: .done("yes\n"))
        _ = harness.run("ask", "7f3a9c21-c1", "which one?", transport: transport)
        _ = harness.run("ask", "7f3a9c21-c1", "which one?", "--wait", "3600", transport: transport)
        #expect(transport.exchanges.current.map(\.idleTimeout) == [15, 15])
    }

    @Test func anAnswerCommandThatIsRefusedExitsOneWithTheAppsLine() {
        let refusal = "7f3a9c21-c1 has no question waiting for an answer"
        for line in [["thread", "answer", "7f3a9c21-c1", "yes"], ["status", "7f3a9c21-c1", "done"], ["ask", "7f3a9c21-c1", "why?"]] {
            let refused = harness.run(line: line, transport: FakeTransport(reply: .refused(refusal)))
            #expect(refused == CommandResult(error: refusal + "\n", exitCode: 1))
        }
    }

    @Test func aCommandRefusedTheLeaseExitsOneWithTheHolderAndTheEndOfTheLease() {
        let refusal = "video-review is in use by Claude Code in /work until 12:01:00 (48s left); "
            + "`video-review control take --wait <seconds>` to queue"
        for line in [["player", "play"], ["control", "take"], ["screenshot", "/tmp/w.png"]] {
            let refused = harness.run(line: line, transport: FakeTransport(reply: .refused(refusal)))
            #expect(refused == CommandResult(error: refusal + "\n", exitCode: 1))
        }
    }

    @Test func eachCommentLineBecomesItsRequest() {
        #expect(request("comment", "add", "the title is small") == .commentAdd(text: "the title is small", at: nil, region: nil))
        #expect(request("comment", "add", "too fast", "--at", "0:10") == .commentAdd(text: "too fast", at: 10, region: nil))
        #expect(request("comment", "add", "--at", "3.5", "too fast") == .commentAdd(text: "too fast", at: 3.5, region: nil))
        let region = WireRegion(x: 0.48, y: 0.3, w: 0.28, h: 0.12)
        #expect(request("comment", "add", "this key", "--region", "0.48,0.30,0.28,0.12") == .commentAdd(text: "this key", at: nil, region: region))
        #expect(request("comment", "add", "this key", "--at", "10", "--region", "0.48,0.30,0.28,0.12") == .commentAdd(text: "this key", at: 10, region: region))
        #expect(request("comment", "add", "--region", "0.48,0.30,0.28,0.12", "--at", "0:10", "this key") == .commentAdd(text: "this key", at: 10, region: region))
        // Whether four numbers lie inside the frame is the app's to say.
        #expect(request("comment", "add", "off the frame", "--region", "-0.1,0,2,2")
            == .commentAdd(text: "off the frame", at: nil, region: WireRegion(x: -0.1, y: 0, w: 2, h: 2)))
        #expect(request("comment", "edit", "7f3a9c21-c1", "new text") == .commentEdit(id: "7f3a9c21-c1", text: "new text"))
        #expect(request("comment", "delete", "7f3a9c21-c1") == .commentDelete(id: "7f3a9c21-c1"))
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
        (["comment", "add"], "comment add: missing <text>", "comment add <text> [--at <time>] [--region x,y,w,h]"),
        (["comment", "add", "late", "--at", "soon"], "comment add: `soon` isn't a time; write seconds (10, 10.5) or mm:ss (0:10)", "comment add <text> [--at <time>] [--region x,y,w,h]"),
        (["comment", "add", "late", "--at"], "comment add: --at needs a value", "comment add <text> [--at <time>] [--region x,y,w,h]"),
        (
            ["comment", "add", "here", "--region", "0.1,0.2,0.3"],
            "comment add: `0.1,0.2,0.3` isn't a region; write x,y,w,h as parts of the frame from 0 to 1 (0.48,0.3,0.28,0.12)",
            "comment add <text> [--at <time>] [--region x,y,w,h]"
        ),
        (["comment", "add", "here", "--region"], "comment add: --region needs a value", "comment add <text> [--at <time>] [--region x,y,w,h]"),
        (["comment", "add", "one", "two"], "comment add: unexpected `two`", "comment add <text> [--at <time>] [--region x,y,w,h]"),
        (["comment", "edit", "7f3a9c21-c1"], "comment edit: missing <text>", "comment edit <id> <text>"),
        (["comment", "delete"], "comment delete: missing <id>", "comment delete <id>"),
        (["app", "open", "--demo"], "app open: --demo needs a value", "app open [--demo <folder>]"),
        (["control", "take", "--wait"], "control take: --wait needs a value", "control take [--wait <s>]"),
        (["control", "take", "--wait", "soon"], "control take: --wait takes whole seconds from 0 to 3600, not `soon`", "control take [--wait <s>]"),
        (["control", "take", "--wait", "3601"], "control take: --wait takes whole seconds from 0 to 3600, not `3601`", "control take [--wait <s>]"),
        (["control", "take", "--wait", "-1"], "control take: --wait takes whole seconds from 0 to 3600, not `-1`", "control take [--wait <s>]"),
        (["control", "take", "30"], "control take: unexpected `30`", "control take [--wait <s>]"),
        (["batch", "send", "now"], "batch send: unexpected `now`", "batch send"),
        (["context", "set"], "context set: missing <text>", "context set <text>"),
        (["context", "set", "a note", "more"], "context set: unexpected `more`", "context set <text>"),
        (["wait", "--timeout"], "wait: --timeout needs a value", "wait [--timeout <s>]"),
        (["wait", "--timeout", "soon"], "wait: --timeout takes whole seconds from 0 to 3600, not `soon`", "wait [--timeout <s>]"),
        (["wait", "--timeout", "3601"], "wait: --timeout takes whole seconds from 0 to 3600, not `3601`", "wait [--timeout <s>]"),
        (["wait", "30"], "wait: unexpected `30`", "wait [--timeout <s>]"),
        (["ack"], "ack: missing <batch-id>", "ack <batch-id> [<text>]"),
        (["ack", "7f3a9c21-b1", "got", "it"], "ack: unexpected `it`", "ack <batch-id> [<text>]"),
        (["status", "7f3a9c21-c1"], "status: missing <working|done|failed>", "status <comment-id> working|done|failed"),
        (
            ["status", "7f3a9c21-c1", "sent"],
            "status: no status `sent`; it takes `working`, `done` or `failed`", "status <comment-id> working|done|failed"
        ),
        (["reply", "7f3a9c21-c1"], "reply: missing <text>", "reply <comment-id|batch-id> <text>"),
        (["ask", "7f3a9c21-c1"], "ask: missing <question>", "ask <comment-id> <question> [--wait <s>]"),
        (["ask", "7f3a9c21-c1", "why?", "--wait"], "ask: --wait needs a value", "ask <comment-id> <question> [--wait <s>]"),
        (
            ["ask", "7f3a9c21-c1", "why?", "--wait", "soon"],
            "ask: --wait takes whole seconds from 0 to 3600, not `soon`", "ask <comment-id> <question> [--wait <s>]"
        ),
        (
            ["ask", "7f3a9c21-c1", "why?", "--wait", "3601"],
            "ask: --wait takes whole seconds from 0 to 3600, not `3601`", "ask <comment-id> <question> [--wait <s>]"
        ),
        (["thread", "answer", "7f3a9c21-c1"], "thread answer: missing <text>", "thread answer <comment-id> <text>"),
        (["thread", "answer"], "thread answer: missing <comment-id>", "thread answer <comment-id> <text>"),
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
