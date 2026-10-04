import Foundation
import Testing
@testable import VRCommand
import VRWire

@Suite struct ContextCommandTests {
    @Test func setReadsItsTextAsOneArgument() throws {
        #expect(try ContextCommand.parse(["set", "Mind the pacing."]).get() == .contextSet(text: "Mind the pacing."))
        // An empty text takes the note away.
        #expect(try ContextCommand.parse(["set", ""]).get() == .contextSet(text: ""))
    }

    @Test(arguments: [
        (["set"], "video-review context set: missing <text>"),
        (["set", "mind", "the pacing"], "video-review context set: unexpected `the pacing`; quote the text"),
        (["show"], "video-review context: unknown command `show`"),
    ])
    func argumentsThatDoNotReadAreTheUsageAndExitTwo(arguments: [String], line: String) {
        guard case .failure(let result) = ContextCommand.parse(arguments) else {
            Issue.record("\(arguments) read")
            return
        }
        #expect(result.status == 2)
        #expect(result.error.hasPrefix(line + "\nusage: video-review context set <text>"))
    }

    @Test func helpIsTheUsageOnStandardOutput() {
        guard case .failure(let result) = ContextCommand.parse(["--help"]) else {
            Issue.record("--help read as a request")
            return
        }
        #expect(result == CommandResult(output: ContextCommand.usageText))
    }

    @Test func theTableSendsContextSetAndPrintsWhatTheAppAnswers() throws {
        let app = try FakeApp()
        app.start(in: app.support)
        app.answer = { _ in .done("context note set\n") }

        #expect(CommandTable.standard.run(["context", "set", "Mind the pacing."], environment: app.environment)
            == CommandResult(output: "context note set\n"))
        #expect(app.requests == [.contextSet(text: "Mind the pacing.")])
    }

    @Test func theTopLevelHelpListsContext() throws {
        let app = try FakeApp()
        #expect(CommandTable.standard.run(["--help"], environment: app.environment).output.contains("  context "))
    }
}
