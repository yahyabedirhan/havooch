import Foundation
import ReviewWire

enum ConnectCommands {
    static let group = CommandGroup(
        name: "connect", summary: "pick, disconnect and forget an agent", section: .drive, commands: [
            Command(
                name: "connect pick", arguments: "<harness>", summary: "pick a harness in the Connect view",
                description: "As a click on its logo does: claude-code, codex, cursor, pi or opencode. It prints the "
                    + "harness's readiness and its prompt.",
                examples: ["claude-code", "codex --window w2"], role: .operator
            ) { arguments, _ throws(UsageError) in
                let harness = try arguments.one("<harness>")
                guard !harness.trimmingCharacters(in: .whitespaces).isEmpty else { throw UsageError("`connect pick` needs a harness's name") }
                return .send(.connectPick(harness: harness))
            },
            Command(
                name: "connect disconnect", summary: "let the window's agent go",
                description: "As Disconnect does: its wait is refused, and its unfinished sends wait for the next agent.",
                examples: [""], role: .operator
            ) { arguments, _ throws(UsageError) in
                try arguments.none()
                return .send(.connectDisconnect)
            },
            Command(
                name: "connect forget", summary: "stop waiting for the agent that reconnects after a relaunch",
                description: "As Forget does.", examples: [""], role: .operator
            ) { arguments, _ throws(UsageError) in
                try arguments.none()
                return .send(.connectForget)
            },
        ].map { $0.onAWindow() }
    )
}
