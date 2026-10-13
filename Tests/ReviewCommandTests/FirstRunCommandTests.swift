import Foundation
import ReviewCommand
import ReviewLease
import ReviewWire
import Testing

@Suite("The first-run commands")
struct FirstRunCommandTests {
    @Test("first-run open, next, back, pick, demo and skip send their requests, to no window", arguments: [
        (["first-run", "open"], ControlRequest.firstRunShow()),
        (["first-run", "open", "connect"], .firstRunShow(step: "connect")),
        (["first-run", "open", "try-it"], .firstRunShow(step: "try-it")),
        (["first-run", "next"], .firstRunNext),
        (["first-run", "back"], .firstRunBack),
        (["first-run", "pick", "codex"], .firstRunPick(harness: "codex")),
        (["first-run", "demo"], .firstRunDemo),
        (["first-run", "skip"], .firstRunSkip),
    ])
    func sends(arguments: [String], request: ControlRequest) {
        let run = Run { _, _ in .success(.done("done\n")) }
        defer { run.cleanUp() }
        #expect(HavoochCLI.run(arguments, environment: run.environment) == CommandResult(output: "done\n"))
        #expect(run.transport.requests == [request])
        #expect(run.transport.sent.map(\.message.window) == [nil])
    }

    @Test("open takes one known step at most, pick one harness; the others take no words", arguments: [
        ["first-run", "open", "later"], ["first-run", "open", "tools", "connect"], ["first-run", "next", "now"],
        ["first-run", "back", "now"], ["first-run", "pick"], ["first-run", "pick", " "], ["first-run", "pick", "codex", "pi"],
        ["first-run", "demo", "now"], ["first-run", "skip", "it"], ["first-run", "open", "--window", "w1"],
    ])
    func usage(arguments: [String]) {
        let run = Run()
        defer { run.cleanUp() }
        #expect(HavoochCLI.run(arguments, environment: run.environment).exitCode == 64)
        #expect(run.transport.requests.isEmpty)
    }

    @Test("the usage text names the first-run commands, and screenshot names the first-run window")
    func usageText() {
        for synopsis in [
            "first-run open [welcome|tools|connect|try-it]", "first-run next", "first-run back", "first-run pick <harness>",
            "first-run demo", "first-run skip",
        ] {
            #expect(CommandTable.usageText.contains("havooch \(synopsis)"))
        }
        #expect(CommandTable.usageText.contains("--window main|settings|about|first-run|<id>"))
    }

    @Test("screenshot --window first-run captures the first-run window")
    func screenshot() {
        let run = Run { _, _ in .success(.done("/tmp/first-run.png\n")) }
        defer { run.cleanUp() }
        _ = HavoochCLI.run(["screenshot", "/tmp/first-run.png", "--window", "first-run"], environment: run.environment)
        #expect(run.transport.requests == [.screenshot(path: "/tmp/first-run.png", appearance: nil, window: .firstRun)])
        #expect(run.transport.sent.map(\.message.window) == [nil])
    }
}
