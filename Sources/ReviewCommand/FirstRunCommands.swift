import Foundation
import ReviewWire

enum FirstRunCommands {
    static let steps = ["welcome", "tools", "connect", "try-it"]

    static let group = CommandGroup(
        name: "first-run", summary: "step through the first-run window", section: .drive, commands: [
            Command(
                name: "first-run open", arguments: "[welcome|tools|connect|try-it]", summary: "show the first-run window",
                description: "As on the first launch, on the step named, as a click on its progress bar does.",
                examples: ["", "connect"], role: .operator
            ) { arguments, _ throws(UsageError) in
                guard arguments.words.count <= 1 else { throw UsageError("unexpected `\(arguments.words[1])`") }
                let step = arguments.words.first
                if let step, !steps.contains(step) {
                    throw UsageError("no step `\(step)`; the steps are \(steps.joined(separator: ", "))")
                }
                return .send(.firstRunShow(step: step))
            },
            Command(
                name: "first-run next", summary: "go to the first-run window's next step",
                description: "As Get Started, Continue and Later go on.", examples: [""], role: .operator
            ) { arguments, _ throws(UsageError) in
                try arguments.none()
                return .send(.firstRunNext)
            },
            Command(
                name: "first-run back", summary: "go to the first-run window's step before",
                description: "As Back does.", examples: [""], role: .operator
            ) { arguments, _ throws(UsageError) in
                try arguments.none()
                return .send(.firstRunBack)
            },
            Command(
                name: "first-run pick", arguments: "<harness>", summary: "pick a harness on the Connect step",
                description: "As a click on its logo does: claude-code, codex, cursor, pi or opencode. It prints its demo prompt.",
                examples: ["claude-code"], role: .operator
            ) { arguments, _ throws(UsageError) in
                let harness = try arguments.one("<harness>")
                guard !harness.trimmingCharacters(in: .whitespaces).isEmpty else { throw UsageError("`first-run pick` needs a harness's name") }
                return .send(.firstRunPick(harness: harness))
            },
            Command(
                name: "first-run demo", summary: "open the bundled demo video and close the first-run window",
                description: "As Open the Demo does.", examples: [""], role: .operator
            ) { arguments, _ throws(UsageError) in
                try arguments.none()
                return .send(.firstRunDemo)
            },
            Command(
                name: "first-run skip", summary: "close the first-run window",
                description: "As Skip Setup and its close button do. Finish setup in the header stays.", examples: [""],
                role: .operator
            ) { arguments, _ throws(UsageError) in
                try arguments.none()
                return .send(.firstRunSkip)
            },
        ]
    )
}
