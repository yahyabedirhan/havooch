import Foundation
import ReviewWire

/// `havooch context set`: the open video's context note, which goes to the
/// agent with the next send.
enum ContextCommands {
    static let group = CommandGroup(
        name: "context", summary: "set the open video's context note", section: .drive, commands: [
            Command(
                name: "context set", arguments: "<text>", summary: "set the open video's context note for the agent",
                description: "The note goes to the agent with the next send. An empty text clears it.",
                examples: ["\"A 20 second launch teaser\"", "\"\""], role: .operator
            ) { arguments, _ throws(UsageError) in
                .send(.contextSet(text: try arguments.one("<text>")))
            }.onAWindow(),
        ]
    )
}
