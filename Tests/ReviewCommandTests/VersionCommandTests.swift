import Foundation
import ReviewCommand
import ReviewLease
import ReviewWire
import Testing

@Suite("The version commands")
struct VersionCommandTests {
    @Test("version show, pick and close send their requests, to the window --window names", arguments: [
        (["version", "show", "3"], ControlRequest.versionShow(number: 3), nil as String?),
        (["version", "show", "v12", "--window", "w2"], .versionShow(number: 12), "w2"),
        (["version", "show", "V7"], .versionShow(number: 7), nil),
        (["version", "pick"], .versionPick(query: ""), nil),
        (["version", "pick", "alt opening"], .versionPick(query: "alt opening"), nil),
        (["version", "close", "--window", "w3"], .versionClose, "w3"),
    ])
    func sends(arguments: [String], request: ControlRequest, window: String?) {
        let run = Run { _, _ in .success(.done("done\n")) }
        defer { run.cleanUp() }
        #expect(HavoochCLI.run(arguments, environment: run.environment) == CommandResult(output: "done\n"))
        #expect(run.transport.requests == [request])
        #expect(run.transport.sent.map(\.message.window) == [window])
    }

    @Test("version show needs one version number, pick one query at most, close none", arguments: [
        ["version", "show"], ["version", "show", "0"], ["version", "show", "v"], ["version", "show", "-2"],
        ["version", "show", "two"], ["version", "show", "1", "2"], ["version", "pick", "a", "b"], ["version", "close", "now"],
    ])
    func usage(arguments: [String]) {
        let run = Run()
        defer { run.cleanUp() }
        #expect(HavoochCLI.run(arguments, environment: run.environment).exitCode == 64)
        #expect(run.transport.requests.isEmpty)
    }

    @Test("the usage text names the version commands")
    func usageText() {
        for synopsis in ["version show <n>", "version pick [<query>]", "version close"] {
            #expect(CommandTable.usageText.contains("havooch \(synopsis)"))
        }
    }
}
