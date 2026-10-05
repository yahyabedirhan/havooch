import Foundation
import ReviewCommand
import ReviewLease
import ReviewWire
import Testing

@Suite("The theme commands")
struct ThemeCommandTests {
    @Test("theme list and theme set send their requests", arguments: [
        (["theme", "list"], ControlRequest.themeList),
        (["theme", "set", "Dimmed"], .themeSet(name: "Dimmed")),
        (["theme", "set", "Default Dark"], .themeSet(name: "Default Dark")),
        (["theme", "set", "system"], .themeSet(name: "system")),
    ])
    func sends(arguments: [String], request: ControlRequest) {
        let run = Run { _, _ in .success(.done("done\n")) }
        defer { run.cleanUp() }
        #expect(VideoReviewCLI.run(arguments, environment: run.environment) == CommandResult(output: "done\n"))
        #expect(run.transport.requests == [request])
    }

    @Test("theme set needs one name, and theme list takes none", arguments: [
        ["theme", "set"], ["theme", "set", ""], ["theme", "set", "Dimmed", "Default Dark"], ["theme", "list", "Dimmed"],
    ])
    func usage(arguments: [String]) {
        let run = Run()
        defer { run.cleanUp() }
        let result = VideoReviewCLI.run(arguments, environment: run.environment)
        #expect(result.exitCode == 64)
        #expect(run.transport.requests.isEmpty)
    }

    @Test("the usage text names both theme commands")
    func usageText() {
        #expect(CommandTable.usageText.contains("video-review theme list"))
        #expect(CommandTable.usageText.contains("video-review theme set <name|system>"))
    }
}
