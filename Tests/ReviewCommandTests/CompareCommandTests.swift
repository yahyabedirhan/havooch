import Foundation
import ReviewCommand
import ReviewLease
import ReviewWire
import Testing

@Suite("The compare commands")
struct CompareCommandTests {
    @Test("compare open, pick, set, swap, start and exit send their requests, to the window --window names", arguments: [
        (["compare", "open"], ControlRequest.compareOpen, nil as String?),
        (["compare", "open", "--window", "w2"], .compareOpen, "w2"),
        (["compare", "pick", "left"], .comparePick(side: .left, query: ""), nil),
        (["compare", "pick", "Right", "alt opening"], .comparePick(side: .right, query: "alt opening"), nil),
        (["compare", "set", "--left", "v1"], .compareSet(CompareChange(left: 1)), nil),
        (["compare", "set", "--right", "3", "--layout", "flip"], .compareSet(CompareChange(right: 3, layout: .flip)), nil),
        (["compare", "set", "--layout", "Side-by-side"], .compareSet(CompareChange(layout: .sideBySide)), nil),
        (["compare", "set", "--side", "left", "--slider", "0.25"], .compareSet(CompareChange(side: .left, slider: 0.25)), nil),
        (["compare", "swap"], .compareSwap, nil),
        (["compare", "start", "--window", "w3"], .compareStart, "w3"),
        (["compare", "exit"], .compareExit, nil),
    ])
    func sends(arguments: [String], request: ControlRequest, window: String?) {
        let run = Run { _, _ in .success(.done("done\n")) }
        defer { run.cleanUp() }
        #expect(HavoochCLI.run(arguments, environment: run.environment) == CommandResult(output: "done\n"))
        #expect(run.transport.requests == [request])
        #expect(run.transport.sent.map(\.message.window) == [window])
    }

    @Test("each compare command takes what it says and refuses the rest", arguments: [
        ["compare", "open", "now"], ["compare", "pick"], ["compare", "pick", "middle"], ["compare", "pick", "left", "a", "b"],
        ["compare", "set"], ["compare", "set", "--left", "0"], ["compare", "set", "--right", "two"],
        ["compare", "set", "--layout", "grid"], ["compare", "set", "--side", "up"], ["compare", "set", "--slider", "1.2"],
        ["compare", "set", "--slider", "half"], ["compare", "set", "3"], ["compare", "swap", "now"], ["compare", "start", "v1"],
        ["compare", "exit", "now"],
    ])
    func usage(arguments: [String]) {
        let run = Run()
        defer { run.cleanUp() }
        #expect(HavoochCLI.run(arguments, environment: run.environment).exitCode == 64)
        #expect(run.transport.requests.isEmpty)
    }

    @Test("the usage text names the compare commands")
    func usageText() {
        for synopsis in ["compare open", "compare pick <left|right> [<query>]", "compare swap", "compare start", "compare exit"] {
            #expect(CommandTable.usageText.contains("havooch \(synopsis)"))
        }
        #expect(CommandTable.usageText.contains("havooch compare set [--left <n>]"))
    }
}
