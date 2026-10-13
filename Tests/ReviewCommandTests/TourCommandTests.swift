import Foundation
import ReviewCommand
import ReviewLease
import ReviewWire
import Testing

@Suite("The tour commands")
struct TourCommandTests {
    @Test("tour open, next, skip and close send their requests, to the window --window names", arguments: [
        (["tour", "open"], ControlRequest.tourShow, nil as String?),
        (["tour", "next"], .tourNext, nil),
        (["tour", "skip", "--window", "w2"], .tourSkip, "w2"),
        (["tour", "close"], .tourClose, nil),
    ])
    func sends(arguments: [String], request: ControlRequest, window: String?) {
        let run = Run { _, _ in .success(.done("done\n")) }
        defer { run.cleanUp() }
        #expect(HavoochCLI.run(arguments, environment: run.environment) == CommandResult(output: "done\n"))
        #expect(run.transport.requests == [request])
        #expect(run.transport.sent.map(\.message.window) == [window])
    }

    @Test("the tour commands take no words", arguments: [
        ["tour", "open", "now"], ["tour", "next", "2"], ["tour", "skip", "it"], ["tour", "close", "it"],
    ])
    func usage(arguments: [String]) {
        let run = Run()
        defer { run.cleanUp() }
        #expect(HavoochCLI.run(arguments, environment: run.environment).exitCode == 2)
        #expect(run.transport.requests.isEmpty)
    }

    @Test("the group's help names the tour commands")
    func usageText() {
        for synopsis in ["tour open", "tour next", "tour skip", "tour close"] {
            #expect(help("tour").contains("havooch \(synopsis)"))
        }
    }
}
