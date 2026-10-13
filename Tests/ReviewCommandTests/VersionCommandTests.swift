import Foundation
import ReviewCommand
import ReviewLease
import ReviewWire
import Testing

@Suite("The version commands")
struct VersionCommandTests {
    @Test("version show and find, and find --close, send their requests, to the window --window names", arguments: [
        (["version", "show", "3"], ControlRequest.versionShow(number: 3), nil as String?),
        (["version", "show", "v12", "--window", "w2"], .versionShow(number: 12), "w2"),
        (["version", "show", "V7"], .versionShow(number: 7), nil),
        (["version", "find"], .versionPick(query: ""), nil),
        (["version", "find", "alt opening"], .versionPick(query: "alt opening"), nil),
        (["version", "find", "--close", "--window", "w3"], .versionClose, "w3"),
    ])
    func sends(arguments: [String], request: ControlRequest, window: String?) {
        let run = Run { _, _ in .success(.done("done\n")) }
        defer { run.cleanUp() }
        #expect(HavoochCLI.run(arguments, environment: run.environment) == CommandResult(output: "done\n"))
        #expect(run.transport.requests == [request])
        #expect(run.transport.sent.map(\.message.window) == [window])
    }

    @Test("version show needs one version number, find one query at most, and none with --close", arguments: [
        ["version", "show"], ["version", "show", "0"], ["version", "show", "v"], ["version", "show", "-2"],
        ["version", "show", "two"], ["version", "show", "1", "2"], ["version", "find", "a", "b"], ["version", "find", "--close", "now"], ["version", "find", "v2", "--close"],
    ])
    func usage(arguments: [String]) {
        let run = Run()
        defer { run.cleanUp() }
        #expect(HavoochCLI.run(arguments, environment: run.environment).exitCode == 2)
        #expect(run.transport.requests.isEmpty)
    }

    @Test("the group's help names the version commands")
    func usageText() {
        for synopsis in ["version show <n>", "version find [<query>] [--close]", "version menu [--search <text>] [--close]", "version section <n> [--remove]"] {
            #expect(help("version").contains("havooch \(synopsis)"))
        }
    }
}
