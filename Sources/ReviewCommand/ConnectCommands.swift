import Foundation
import ReviewWire

/// `havooch connect show | pick <harness> | disconnect | forget`: the
/// Connect view's own actions, each the operator's, as the person's clicks
/// are. Back is `thread list`; Link, Run Command and Cancel are `setup link`,
/// `setup install` and `setup cancel`. Copying a prompt or a path changes
/// nothing in the app: `state --json` has the text under `sidebar.connect`.
enum ConnectCommands {
    static let commands: [Command] = [
        Command(
            name: "connect show", synopsis: "connect show",
            summary: "show the Connect view in the sidebar, as the header's connect button does; thread list goes back"
        ) { arguments, _ throws(UsageError) in
            try arguments.none()
            return .send(.connectShow)
        },
        Command(
            name: "connect pick", synopsis: "connect pick <harness>",
            summary: "pick a harness in the Connect view (claude-code, codex, cursor, pi, opencode), as a click on its logo does; prints its readiness and its prompt"
        ) { arguments, _ throws(UsageError) in
            let harness = try arguments.one("<harness>")
            guard !harness.trimmingCharacters(in: .whitespaces).isEmpty else { throw UsageError("`connect pick` needs a harness's name") }
            return .send(.connectPick(harness: harness))
        },
        Command(
            name: "connect disconnect", synopsis: "connect disconnect",
            summary: "let the window's agent go, as Disconnect does: its wait is refused and its unfinished sends wait for the next agent"
        ) { arguments, _ throws(UsageError) in
            try arguments.none()
            return .send(.connectDisconnect)
        },
        Command(
            name: "connect forget", synopsis: "connect forget",
            summary: "stop waiting for the agent that reconnects after a relaunch, as Forget does"
        ) { arguments, _ throws(UsageError) in
            try arguments.none()
            return .send(.connectForget)
        },
    ]
}
