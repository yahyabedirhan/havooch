import Foundation
import ReviewCommand
import ReviewLease
import ReviewWire
import Testing

@Suite("The setup commands")
struct SetupCommandTests {
    @Test("setup status, link, install and cancel send their requests", arguments: [
        (["setup", "status"], ControlRequest.setupStatus),
        (["setup", "link"], .setupLink()),
        (["setup", "link", "--dry-run"], .setupLink(dryRun: true)),
        (["setup", "install"], .setupInstall()),
        (["setup", "install", "--harness", "codex", "--harness", "pi"], .setupInstall(harnesses: ["codex", "pi"])),
        (["setup", "install", "--dry-run"], .setupInstall(dryRun: true)),
        (["setup", "cancel"], .setupCancel),
    ])
    func sends(arguments: [String], request: ControlRequest) {
        let run = Run { _, _ in .success(.done("done\n")) }
        defer { run.cleanUp() }
        #expect(HavoochCLI.run(arguments, environment: run.environment) == CommandResult(output: "done\n"))
        #expect(run.transport.requests == [request])
    }

    @Test("the setup commands take no words, and --harness needs a name", arguments: [
        ["setup", "status", "now"], ["setup", "link", "here"], ["setup", "install", "codex"], ["setup", "install", "--harness"],
        ["setup", "install", "--harness", " "], ["setup", "cancel", "it"], ["setup", "link", "--force"],
    ])
    func usage(arguments: [String]) {
        let run = Run()
        defer { run.cleanUp() }
        #expect(HavoochCLI.run(arguments, environment: run.environment).exitCode == 64)
        #expect(run.transport.requests.isEmpty)
    }

    @Test("a refused link prints the ln -sf line and exits 1")
    func refusedLink() {
        let reason = "/Users/me/.local/bin/havooch is already there and isn't a link, so Havooch leaves it alone. "
            + "Run this in a terminal: mkdir -p ~/.local/bin && ln -sf /Applications/Havooch.app/Contents/Helpers/havooch ~/.local/bin/havooch"
        let run = Run { _, _ in .success(.refused(reason)) }
        defer { run.cleanUp() }
        let result = HavoochCLI.run(["setup", "link"], environment: run.environment)
        #expect(result.exitCode == 1)
        #expect(result.error.contains("ln -sf /Applications/Havooch.app/Contents/Helpers/havooch ~/.local/bin/havooch"))
    }

    @Test("the usage text names the setup commands")
    func usageText() {
        for synopsis in ["setup status", "setup link [--dry-run]", "setup install [--harness <name>]... [--dry-run]", "setup cancel"] {
            #expect(CommandTable.usageText.contains("havooch \(synopsis)"))
        }
    }
}
