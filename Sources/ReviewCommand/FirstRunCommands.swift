import Foundation
import ReviewWire

/// `havooch first-run show [<step>] | next | back | pick <harness> | demo
/// | skip`: the first-run window, which shows by itself on the first
/// launch only. Each is the operator's, as the person's clicks are. Link,
/// Run Command and Cancel on its Tools step are `setup link`, `setup install`
/// and `setup cancel`; copying the demo prompt changes nothing in the app:
/// `state --json` has it under `firstRun.prompt`.
enum FirstRunCommands {
    /// The steps, in order, as `first-run show` and `state` name them.
    static let steps = ["welcome", "tools", "connect", "try-it"]

    static let commands: [Command] = [
        Command(
            name: "first-run show", synopsis: "first-run show [welcome|tools|connect|try-it]",
            summary: "show the first-run window, as on the first launch, on a step as a click on its progress bar does"
        ) { arguments, _ throws(UsageError) in
            guard arguments.words.count <= 1 else { throw UsageError("unexpected `\(arguments.words[1])`") }
            let step = arguments.words.first
            if let step, !steps.contains(step) {
                throw UsageError("no step `\(step)`; the steps are \(steps.joined(separator: ", "))")
            }
            return .send(.firstRunShow(step: step))
        },
        Command(
            name: "first-run next", synopsis: "first-run next",
            summary: "the first-run window's next step, as Get Started, Continue and Later go on"
        ) { arguments, _ throws(UsageError) in
            try arguments.none()
            return .send(.firstRunNext)
        },
        Command(name: "first-run back", synopsis: "first-run back", summary: "the first-run window's step before, as Back") {
            arguments, _ throws(UsageError) in
            try arguments.none()
            return .send(.firstRunBack)
        },
        Command(
            name: "first-run pick", synopsis: "first-run pick <harness>",
            summary: "pick a harness on the Connect step (claude-code, codex, cursor, pi, opencode), as a click on its logo does; prints its demo prompt"
        ) { arguments, _ throws(UsageError) in
            let harness = try arguments.one("<harness>")
            guard !harness.trimmingCharacters(in: .whitespaces).isEmpty else { throw UsageError("`first-run pick` needs a harness's name") }
            return .send(.firstRunPick(harness: harness))
        },
        Command(
            name: "first-run demo", synopsis: "first-run demo",
            summary: "open the bundled demo video for the person and close the first-run window, as Open the Demo does"
        ) { arguments, _ throws(UsageError) in
            try arguments.none()
            return .send(.firstRunDemo)
        },
        Command(
            name: "first-run skip", synopsis: "first-run skip",
            summary: "close the first-run window, as Skip Setup and its close button do; Finish setup in the header stays"
        ) { arguments, _ throws(UsageError) in
            try arguments.none()
            return .send(.firstRunSkip)
        },
    ]
}
