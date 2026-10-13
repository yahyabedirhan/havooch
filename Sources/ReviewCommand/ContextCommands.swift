import Foundation
import ReviewWire

/// `havooch context set`: the open video's context note, which goes to the
/// agent with the next send.
enum ContextCommands {
    static let commands: [Command] = [
        Command(
            name: "context set", synopsis: "context set <text>",
            summary: "set the open video's context note for the agent; an empty text clears it"
        ) { arguments, _ throws(UsageError) in
            .send(.contextSet(text: try arguments.one("<text>")))
        },
    ]
}
