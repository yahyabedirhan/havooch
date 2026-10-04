import Foundation
import Testing
@testable import VRCommand
import VRWire

@Suite struct CommentCommandTests {
    @Test func addReadsItsTextAndItsTime() throws {
        #expect(try CommentCommand.parse(["add", "too fast"]).get() == .commentAdd(text: "too fast", at: nil))
        #expect(try CommentCommand.parse(["add", "too fast", "--at", "0:10"]).get() == .commentAdd(text: "too fast", at: 10))
        #expect(try CommentCommand.parse(["add", "--at", "10.5", "too fast"]).get() == .commentAdd(text: "too fast", at: 10.5))
        // A text that starts with a dash is still the text.
        #expect(try CommentCommand.parse(["add", "-3 dB would be better"]).get() == .commentAdd(text: "-3 dB would be better", at: nil))
    }

    @Test func editAndDeleteReadTheirId() throws {
        #expect(try CommentCommand.parse(["edit", "c1", "slower here"]).get() == .commentEdit(id: "c1", text: "slower here"))
        #expect(try CommentCommand.parse(["delete", "c1"]).get() == .commentDelete(id: "c1"))
    }

    @Test(arguments: [
        (["add"], "video-review comment add: missing <text>"),
        (["add", "  "], "video-review comment add: missing <text>"),
        (["add", "--at", "0:10"], "video-review comment add: missing <text>"),
        (["add", "too", "fast"], "video-review comment add: unexpected `fast`; quote the text"),
        (["add", "x", "--at"], "video-review comment add: --at needs a time"),
        (["add", "x", "--at", "soon"], "video-review comment add: `soon` isn't a time; use seconds, mm:ss or h:mm:ss"),
        (["add", "x", "--loud"], "video-review comment add: unknown option `--loud`"),
        (["edit"], "video-review comment edit: missing <id>"),
        (["edit", "c1"], "video-review comment edit: missing <text>"),
        (["edit", "c1", ""], "video-review comment edit: missing <text>"),
        (["edit", "c1", "slower", "here"], "video-review comment edit: unexpected `here`; quote the text"),
        (["delete"], "video-review comment delete: missing <id>"),
        (["delete", "c1", "c2"], "video-review comment delete: unexpected `c2`"),
        (["remove", "c1"], "video-review comment: unknown command `remove`"),
    ])
    func argumentsThatDoNotReadAreTheUsageAndExitTwo(arguments: [String], line: String) {
        guard case .failure(let result) = CommentCommand.parse(arguments) else {
            Issue.record("\(arguments) read")
            return
        }
        #expect(result.status == 2)
        #expect(result.error.hasPrefix(line + "\nusage: video-review comment"))
    }

    @Test func theTableSendsACommentToTheAppAndPrintsItsAnswer() throws {
        let app = try FakeApp()
        app.start(in: app.support)
        app.answer = { _ in .done("c1 at 0:10.000\n") }
        let table = CommandTable.standard

        let result = table.run(["comment", "add", "too fast", "--at", "0:10", "--json"], environment: app.environment)

        #expect(result == CommandResult(output: "c1 at 0:10.000\n"))
        #expect(app.requests == [.commentAdd(text: "too fast", at: 10)])
        #expect(app.messages.map(\.json) == [true])
    }

    @Test func helpNeedsNoAppAndIsInTheTopLevelHelp() throws {
        let app = try FakeApp()
        let table = CommandTable.standard

        let help = table.run(["comment", "--help"], environment: app.environment)

        #expect(help.status == 0)
        #expect(help.output.hasPrefix("usage: video-review comment add"))
        #expect(table.run(["--help"], environment: app.environment).output.contains("  comment "))
        #expect(app.requests.isEmpty)
    }
}
