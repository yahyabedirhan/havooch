import Foundation
import ReviewCommand
import ReviewLease
import ReviewWire
import Testing

@Suite("The commands that take more than one form")
struct MergedCommandTests {
    @Test("popover open opens a new message's popover, or a thread's with --thread, to the window --window names", arguments: [
        (["popover", "open"], ControlRequest.commentOpen(text: ""), nil as String?),
        (["popover", "open", "Too fast", "--region", "0.25,0.2,0.3,0.25"],
         .commentOpen(text: "Too fast", region: .init(x: 0.25, y: 0.2, w: 0.3, h: 0.25)), nil),
        (["popover", "open", "--thread", "3"], .threadOpen(thread: "3"), nil),
        (["popover", "open", "--thread", "t-f92cbb2a-3", "--frame", "0.55,0.1,0.4,0.5", "--window", "w2"],
         .threadOpen(thread: "t-f92cbb2a-3", frame: .init(x: 0.55, y: 0.1, w: 0.4, h: 0.5)), "w2"),
    ])
    func popover(arguments: [String], request: ControlRequest, window: String?) {
        let run = Run { _, _ in .success(.done("done\n")) }
        defer { run.cleanUp() }
        #expect(HavoochCLI.run(arguments, environment: run.environment) == CommandResult(output: "done\n"))
        #expect(run.transport.requests == [request])
        #expect(run.transport.sent.map(\.message.window) == [window])
    }

    @Test("sidebar show shows the sidebar, or the view it names in it, to the window --window names", arguments: [
        (["sidebar", "show"], ControlRequest.sidebarVisibility(show: true), nil as String?),
        (["sidebar", "show", "threads"], .threadList, nil),
        (["sidebar", "show", "thread", "3"], .threadShow(thread: "3"), nil),
        (["sidebar", "show", "thread", "t-f92cbb2a-1", "--window", "w2"], .threadShow(thread: "t-f92cbb2a-1"), "w2"),
        (["sidebar", "show", "connect", "--window", "w3"], .connectShow, "w3"),
    ])
    func sidebar(arguments: [String], request: ControlRequest, window: String?) {
        let run = Run { _, _ in .success(.done("done\n")) }
        defer { run.cleanUp() }
        #expect(HavoochCLI.run(arguments, environment: run.environment) == CommandResult(output: "done\n"))
        #expect(run.transport.requests == [request])
        #expect(run.transport.sent.map(\.message.window) == [window])
    }

    @Test("version find opens the picker with a query, and --close closes it", arguments: [
        (["version", "find"], ControlRequest.versionPick(query: "")),
        (["version", "find", "alt opening"], .versionPick(query: "alt opening")),
        (["version", "find", "--close"], .versionClose),
    ])
    func versionFind(arguments: [String], request: ControlRequest) {
        let run = Run { _, _ in .success(.done("done\n")) }
        defer { run.cleanUp() }
        #expect(HavoochCLI.run(arguments, environment: run.environment) == CommandResult(output: "done\n"))
        #expect(run.transport.requests == [request])
    }

    @Test("a merged command refuses one form's words in the other's, and a view it doesn't have", arguments: [
        ["popover", "open", "--thread", "2", "hello"], ["popover", "open", "--thread", "2", "--region", "0.25,0.2,0.3,0.25"],
        ["popover", "open", "hello", "--frame", "0.55,0.1,0.4,0.5"],
        ["sidebar", "show", "thread"], ["sidebar", "show", "thread", "1", "2"], ["sidebar", "show", "threads", "1"],
        ["sidebar", "show", "connect", "now"], ["sidebar", "show", "settings"],
        ["version", "find", "v2", "--close"],
    ])
    func usage(arguments: [String]) {
        let run = Run()
        defer { run.cleanUp() }
        let result = HavoochCLI.run(arguments, environment: run.environment)
        #expect(result.exitCode == 2)
        #expect(result.error.contains("usage: havooch \(arguments[0]) \(arguments[1])"))
        #expect(run.transport.requests.isEmpty)
    }

    @Test("the old names are unknown commands", arguments: [
        ["status", "m-f92cbb2a-1", "done"], ["send"], ["player", "open", "/a.mp4"], ["comment", "add", "Too fast"],
        ["comment", "edit", "m-1", "Slower"], ["comment", "delete", "m-1"], ["comment", "open"], ["comment", "compose"],
        ["thread", "open", "1"], ["thread", "show", "1"], ["thread", "list"], ["thread", "versions"], ["thread", "version", "2"],
        ["connect", "show"], ["version", "pick"], ["version", "close"], ["compare", "pick", "left"], ["tour", "show"],
        ["first-run", "show"], ["config", "dismiss"],
    ])
    func oldNames(arguments: [String]) {
        let run = Run()
        defer { run.cleanUp() }
        let result = HavoochCLI.run(arguments, environment: run.environment)
        #expect(result.exitCode == 2)
        #expect(result.error.hasPrefix("havooch: unknown command"))
        #expect(run.transport.requests.isEmpty)
    }
}
