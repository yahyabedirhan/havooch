import Foundation
import ReviewCommand
import ReviewLease
import ReviewWire
import Testing

@Suite("The first-run commands")
struct FirstRunCommandTests {
    @Test("first-run show, next, back, pick, demo and skip send their requests, to no window", arguments: [
        (["first-run", "show"], ControlRequest.firstRunShow()),
        (["first-run", "show", "connect"], .firstRunShow(step: "connect")),
        (["first-run", "show", "try-it"], .firstRunShow(step: "try-it")),
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

    @Test("show takes one known step at most, pick one harness; the others take no words", arguments: [
        ["first-run", "show", "later"], ["first-run", "show", "tools", "connect"], ["first-run", "next", "now"],
        ["first-run", "back", "now"], ["first-run", "pick"], ["first-run", "pick", " "], ["first-run", "pick", "codex", "pi"],
        ["first-run", "demo", "now"], ["first-run", "skip", "it"], ["first-run", "show", "--window", "w1"],
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
            "first-run show [welcome|tools|connect|try-it]", "first-run next", "first-run back", "first-run pick <harness>",
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
