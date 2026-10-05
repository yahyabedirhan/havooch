import Foundation
import Testing
@testable import VRCommand
import VRWire

private let table = CommandTable.standard

/// `ack`, `status`, `reply`, `ask` and `thread answer` as the command reads
/// and prints them.
@Suite struct AnswerCommandTests {
    @Test func theArgumentsReadAsTheirRequests() throws {
        #expect(try ListenerCommand.parseAck(["b1"]).get() == .ack(batchID: "b1", text: nil))
        #expect(try ListenerCommand.parseAck(["b1", "on it"]).get() == .ack(batchID: "b1", text: "on it"))
        #expect(try ListenerCommand.parseReply(["c1", "fixed in abc123"]).get() == .reply(id: "c1", text: "fixed in abc123"))
        #expect(try ListenerCommand.parseReply(["b1", "-3 dB it is"]).get() == .reply(id: "b1", text: "-3 dB it is"))
        #expect(try ListenerCommand.parseAsk(["c1", "which part?"]).get()
            == .ask(commentID: "c1", question: "which part?", waitSeconds: nil))
        #expect(try ListenerCommand.parseAsk(["c1", "which part?", "--wait", "30"]).get()
            == .ask(commentID: "c1", question: "which part?", waitSeconds: 30))
        #expect(try ListenerCommand.parseAsk(["--wait", "0", "c1", "which part?"]).get()
            == .ask(commentID: "c1", question: "which part?", waitSeconds: 0))
        #expect(try ThreadCommand.parse(["answer", "c1", "the intro"]).get() == .threadAnswer(commentID: "c1", text: "the intro"))
    }

    @Test(arguments: ["working", "done", "failed"])
    func aStatusReadsAsItsRequest(state: String) throws {
        #expect(try ListenerCommand.parseStatus(["c1", state]).get() == .status(commentID: "c1", state: state))
    }

    @Test(arguments: [
        (["ack"], "video-review ack: missing <batch-id>", "usage: video-review ack"),
        (["ack", "b1", "on", "it"], "video-review ack: unexpected `it`; quote the text", "usage: video-review ack"),
        (["ack", "b1", " "], "video-review ack: the text is empty; leave it out", "usage: video-review ack"),
        (["status"], "video-review status: missing <comment-id>", "usage: video-review status"),
        (["status", "c1"], "video-review status: missing working, done or failed", "usage: video-review status"),
        (["status", "c1", "sent"], "video-review status: `sent` isn't a status; use working, done or failed", "usage: video-review status"),
        (["status", "c1", "done", "now"], "video-review status: unexpected `now`", "usage: video-review status"),
        (["reply"], "video-review reply: missing <comment-id|batch-id>", "usage: video-review reply"),
        (["reply", "c1"], "video-review reply: missing <text>", "usage: video-review reply"),
        (["reply", "c1", ""], "video-review reply: missing <text>", "usage: video-review reply"),
        (["reply", "c1", "two", "words"], "video-review reply: unexpected `words`; quote the text", "usage: video-review reply"),
        (["ask"], "video-review ask: missing <comment-id>", "usage: video-review ask"),
        (["ask", "c1"], "video-review ask: missing <question>", "usage: video-review ask"),
        (["ask", "c1", "why", "so"], "video-review ask: unexpected `so`; quote the text", "usage: video-review ask"),
        (["ask", "c1", "why?", "--wait"], "video-review ask: --wait needs a number of seconds", "usage: video-review ask"),
        (["ask", "c1", "why?", "--wait", "soon"],
         "video-review ask: --wait takes whole seconds from 0 to 86400, not `soon`", "usage: video-review ask"),
        (["ask", "c1", "why?", "--wait", "86401"],
         "video-review ask: --wait takes whole seconds from 0 to 86400, not `86401`", "usage: video-review ask"),
        (["ask", "c1", "why?", "--timeout", "5"], "video-review ask: unknown option `--timeout`", "usage: video-review ask"),
        (["thread", "answer"], "video-review thread answer: missing <comment-id>", "usage: video-review thread answer"),
        (["thread", "answer", "c1"], "video-review thread answer: missing <text>", "usage: video-review thread answer"),
        (["thread", "answer", "c1", "a", "b"],
         "video-review thread answer: unexpected `b`; quote the text", "usage: video-review thread answer"),
        (["thread", "reply", "c1", "a"], "video-review thread: unknown command `reply`", "usage: video-review thread answer"),
    ])
    func argumentsThatDoNotReadAreTheUsageAndExitTwoAndNothingIsSent(arguments: [String], line: String, usage: String) throws {
        let app = try FakeApp()
        app.start(in: app.support)

        let result = table.run(arguments, environment: app.environment)

        #expect(result.status == 2)
        #expect(result.output.isEmpty)
        #expect(result.error.hasPrefix(line + "\n" + usage))
        #expect(app.requests.isEmpty)
    }

    @Test(arguments: ["thread", "wait", "ack", "status", "reply", "ask"])
    func theTableHasTheCommandAndItExplainsItselfWithoutTheApp(command: String) throws {
        let app = try FakeApp()
        let help = table.run(["--help"], environment: app.environment).output

        #expect(help.contains("  \(command) "))
        let result = table.run([command, "--help"], environment: app.environment)
        #expect(result.status == 0)
        #expect(result.output.hasPrefix("usage: video-review \(command)"))
        #expect(app.requests.isEmpty)
    }

    @Test func eachCommandSendsItsRequestAndPrintsWhatTheAppAnswers() throws {
        let app = try FakeApp()
        app.start(in: app.support)
        app.answer = { _ in .done("the app's words\n") }

        for arguments in [
            ["ack", "b1", "on it"], ["status", "c1", "working"], ["reply", "c1", "fixed"],
            ["ask", "c1", "which part?", "--wait", "5"], ["thread", "answer", "c1", "the intro"],
        ] {
            #expect(table.run(arguments, environment: app.environment) == CommandResult(output: "the app's words\n"))
        }
        #expect(app.requests == [
            .ack(batchID: "b1", text: "on it"), .status(commentID: "c1", state: "working"), .reply(id: "c1", text: "fixed"),
            .ask(commentID: "c1", question: "which part?", waitSeconds: 5), .threadAnswer(commentID: "c1", text: "the intro"),
        ])
    }

    @Test func jsonIsAskedOfTheAppForAnAnswerToo() throws {
        let app = try FakeApp()
        app.start(in: app.support)

        _ = table.run(["ask", "c1", "which part?", "--json"], environment: app.environment)
        _ = table.run(["--json", "status", "c1", "done"], environment: app.environment)

        #expect(app.messages.map(\.json) == [true, true])
    }

    @Test func anAskWhoseTimeRanOutExitsThreeWithNothingOnStandardOutput() throws {
        let app = try FakeApp()
        app.start(in: app.support)
        app.answer = { _ in .done("", note: "no answer came within 5 seconds\n") }

        #expect(table.run(["ask", "c1", "which part?", "--wait", "5"], environment: app.environment)
            == CommandResult(error: "no answer came within 5 seconds\n", status: 3))
    }

    @Test func aRefusedAnswerExitsOne() throws {
        let app = try FakeApp()
        app.start(in: app.support)
        app.answer = { _ in .refused("c1 is done; it can't be set to working") }

        #expect(table.run(["status", "c1", "working"], environment: app.environment)
            == CommandResult(error: "c1 is done; it can't be set to working\n", status: 1))
        #expect(table.run(["ask", "c1", "why?"], environment: app.environment).status == 1)
        // Not running at all is exit 1 too.
        #expect(table.run(["ack", "b1"], environment: try FakeApp().environment).status == 1)
    }

    @Test func anAskIsReadForAsLongAsTheAppKeepsItsConnectionAliveAndTheOthersAreNot() throws {
        let app = try FakeApp()
        app.start(in: app.support)

        _ = table.run(["ask", "c1", "why?"], environment: app.environment)
        _ = table.run(["ask", "c1", "why?", "--wait", "600"], environment: app.environment)
        _ = table.run(["reply", "c1", "ok"], environment: app.environment)
        _ = table.run(["thread", "answer", "c1", "ok"], environment: app.environment)

        #expect(app.timeouts == [
            ControlClient.longestSilence, ControlClient.longestSilence, ControlClient.defaultTimeout, ControlClient.defaultTimeout,
        ])
    }
}
