import Foundation
import ReviewWire

/// `havooch control take [--timeout <seconds>] | release`: holding the
/// lease on purpose and giving it up. Both are free commands: `take` is how
/// an agent asks for the lease, and `release` from anyone but the holder
/// changes nothing.
enum ControlCommands {
    static let group = CommandGroup(
        name: "control", summary: "take and release the lease", section: .drive, commands: [
            Command(
                name: "control take", arguments: "[--timeout <seconds>]", summary: "hold the app for 5 minutes",
                description: "Each command that drives the app renews the lease. Without --timeout it fails at once while "
                    + "another agent holds the lease; with it, it waits in line, first come first served.",
                examples: ["", "--timeout 120"], role: .free,
                exitCodes: "1 when another agent holds the lease, 124 when --timeout runs out in line.",
                valuedOptions: ["--timeout"]
            ) { arguments, _ throws(UsageError) in
                try arguments.none()
                guard let seconds = arguments.options["--timeout"] else { return .send(.controlTake(waitSeconds: nil)) }
                guard let whole = Int(seconds), (0...ControlRequest.longestWait).contains(whole) else {
                    throw UsageError("`--timeout` takes whole seconds from 0 to \(ControlRequest.longestWait), not `\(seconds)`")
                }
                return .send(.controlTake(waitSeconds: whole))
            },
            Command(
                name: "control release", summary: "give the app up, so the next agent in line gets it",
                examples: [""], role: .free
            ) { arguments, _ throws(UsageError) in
                try arguments.none()
                return .send(.controlRelease)
            },
        ]
    )
}
