import Foundation
import Testing
@testable import VRCommand
import VRWire

@Suite struct BatchCommandTests {
    @Test func sendReads() throws {
        #expect(try BatchCommand.parse(["send"]).get() == .batchSend)
    }

    @Test(arguments: [
        (["send", "now"], "video-review batch send: unexpected `now`"),
        (["post"], "video-review batch: unknown command `post`"),
    ])
    func argumentsThatDoNotReadAreTheUsageAndExitTwo(arguments: [String], line: String) {
        guard case .failure(let result) = BatchCommand.parse(arguments) else {
            Issue.record("\(arguments) read")
            return
        }
        #expect(result.status == 2)
        #expect(result.error.hasPrefix(line + "\nusage: video-review batch send"))
    }

    @Test func batchSendPrintsWhatTheAppAnswers() throws {
        let app = try FakeApp()
        app.start(in: app.support)
        app.answer = { _ in .done("sent b1 with 2 comments\n") }

        #expect(CommandTable.standard.run(["batch", "send"], environment: app.environment)
            == CommandResult(output: "sent b1 with 2 comments\n"))
        #expect(app.requests == [.batchSend])
    }
}

@Suite struct ListenerCommandTests {
    @Test func waitReadsItsTimeout() throws {
        #expect(try ListenerCommand.parseWait([]).get() == .wait(timeoutSeconds: nil))
        #expect(try ListenerCommand.parseWait(["--timeout", "0"]).get() == .wait(timeoutSeconds: 0))
        #expect(try ListenerCommand.parseWait(["--timeout", "30"]).get() == .wait(timeoutSeconds: 30))
    }

    @Test(arguments: [
        (["now"], "video-review wait: unexpected `now`"),
        (["--timeout"], "video-review wait: --timeout needs a number of seconds"),
        (["--timeout", "soon"], "video-review wait: --timeout takes whole seconds from 0 to 86400, not `soon`"),
        (["--timeout", "-1"], "video-review wait: --timeout takes whole seconds from 0 to 86400, not `-1`"),
        (["--timeout", "86401"], "video-review wait: --timeout takes whole seconds from 0 to 86400, not `86401`"),
        (["--timeout", "5", "6"], "video-review wait: unexpected `6`"),
    ])
    func argumentsThatDoNotReadAreTheUsageAndExitTwo(arguments: [String], line: String) {
        guard case .failure(let result) = ListenerCommand.parseWait(arguments) else {
            Issue.record("\(arguments) read")
            return
        }
        #expect(result.status == 2)
        #expect(result.error.hasPrefix(line + "\nusage: video-review wait"))
    }

    @Test func aBatchIsPrintedAsTheAppSentItWithExitZero() throws {
        let app = try FakeApp()
        app.start(in: app.support)
        app.answer = { _ in .done(#"{"batch":{"id":"b1"}}"# + "\n") }

        #expect(CommandTable.standard.run(["wait", "--timeout", "5"], environment: app.environment)
            == CommandResult(output: #"{"batch":{"id":"b1"}}"# + "\n"))
        #expect(app.requests == [.wait(timeoutSeconds: 5)])
    }

    @Test func aWaitWhoseTimeRanOutExitsThreeWithNothingOnStandardOutput() throws {
        let app = try FakeApp()
        app.start(in: app.support)
        app.answer = { _ in .done("", note: "no batch came within 5 seconds\n") }

        #expect(CommandTable.standard.run(["wait", "--timeout", "5"], environment: app.environment)
            == CommandResult(error: "no batch came within 5 seconds\n", status: 3))
    }

    @Test func aRefusedWaitExitsOne() throws {
        let app = try FakeApp()
        app.start(in: app.support)
        app.answer = { _ in .refused("video-review is quitting") }

        #expect(CommandTable.standard.run(["wait"], environment: app.environment)
            == CommandResult(error: "video-review is quitting\n", status: 1))
        // Not running at all is exit 1 too.
        #expect(CommandTable.standard.run(["wait"], environment: try FakeApp().environment).status == 1)
    }

    @Test func aWaitIsReadForAsLongAsTheAppKeepsItsConnectionAlive() throws {
        let app = try FakeApp()
        app.start(in: app.support)

        _ = CommandTable.standard.run(["wait"], environment: app.environment)
        _ = CommandTable.standard.run(["wait", "--timeout", "600"], environment: app.environment)
        _ = CommandTable.standard.run(["batch", "send"], environment: app.environment)

        // A wait's read gives up after a silence, however long it waits.
        #expect(app.timeouts == [ControlClient.longestSilence, ControlClient.longestSilence, ControlClient.defaultTimeout])
    }
}
