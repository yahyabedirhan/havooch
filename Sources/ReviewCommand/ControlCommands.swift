import Foundation
import ReviewWire

/// `havooch control take [--timeout <seconds>] | release`: holding the
/// lease on purpose and giving it up. Both are free commands: `take` is how
/// an agent asks for the lease, and `release` from anyone but the holder
/// changes nothing.
enum ControlCommands {
    static let commands: [Command] = [
        Command(
            name: "control take", synopsis: "control take [--timeout <seconds>]",
            summary: "hold the app for 5 minutes; --timeout queues behind another agent, first come first served, and exits 124 when it runs out",
            valuedOptions: ["--timeout"]
        ) { arguments, _ throws(UsageError) in
            try arguments.none()
            guard let seconds = arguments.options["--timeout"] else { return .send(.controlTake(waitSeconds: nil)) }
            guard let whole = Int(seconds), (0...ControlRequest.longestWait).contains(whole) else {
                throw UsageError("`--timeout` takes whole seconds from 0 to \(ControlRequest.longestWait), not `\(seconds)`")
            }
            return .send(.controlTake(waitSeconds: whole))
        },
        Command(name: "control release", synopsis: "control release", summary: "give the app up, so the next agent in line gets it") {
            arguments, _ throws(UsageError) in
            try arguments.none()
            return .send(.controlRelease)
        },
    ]
}
