import Foundation
import ReviewCommand
import ReviewLease
import ReviewWire
import Testing

@Suite("The connect commands")
struct ConnectCommandTests {
    @Test("connect show, pick, disconnect and forget send their requests, to the window --window names", arguments: [
        (["connect", "show"], ControlRequest.connectShow, nil as String?),
        (["connect", "pick", "codex"], .connectPick(harness: "codex"), nil),
        (["connect", "pick", "claude-code", "--window", "w2"], .connectPick(harness: "claude-code"), "w2"),
        (["connect", "disconnect", "--window", "w2"], .connectDisconnect, "w2"),
        (["connect", "forget"], .connectForget, nil),
    ])
    func sends(arguments: [String], request: ControlRequest, window: String?) {
        let run = Run { _, _ in .success(.done("done\n")) }
        defer { run.cleanUp() }
        #expect(HavoochCLI.run(arguments, environment: run.environment) == CommandResult(output: "done\n"))
        #expect(run.transport.requests == [request])
        #expect(run.transport.sent.map(\.message.window) == [window])
    }

    @Test("connect pick needs one harness; the others take no words", arguments: [
        ["connect", "show", "now"], ["connect", "pick"], ["connect", "pick", " "], ["connect", "pick", "codex", "pi"],
        ["connect", "disconnect", "it"], ["connect", "forget", "it"],
    ])
    func usage(arguments: [String]) {
        let run = Run()
        defer { run.cleanUp() }
        #expect(HavoochCLI.run(arguments, environment: run.environment).exitCode == 64)
        #expect(run.transport.requests.isEmpty)
    }

    @Test("the usage text names the connect commands")
    func usageText() {
        for synopsis in ["connect show", "connect pick <harness>", "connect disconnect", "connect forget"] {
            #expect(CommandTable.usageText.contains("havooch \(synopsis)"))
        }
    }
}
