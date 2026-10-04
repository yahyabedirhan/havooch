import Foundation
import ReviewWire

/// `video-review comment add | edit | delete`.
enum CommentCommands {
    static let commands: [Command] = [
        Command(
            name: "comment add", synopsis: "comment add <text> [--at <time>]",
            summary: "queue a comment at a time, or where the player is",
            valuedOptions: ["--at"]
        ) { arguments, _ throws(UsageError) in
            let text = try arguments.one("<text>")
            var at: Double?
            if let time = arguments.options["--at"] {
                guard let seconds = TimeCode.seconds(time) else {
                    throw UsageError("`\(time)` isn't a time; write seconds (`90`, `12.5`) or `mm:ss` (`1:30`)")
                }
                at = seconds
            }
            return .send(.commentAdd(text: text, at: at))
        },
        Command(name: "comment edit", synopsis: "comment edit <id> <text>", summary: "change a queued comment's text") {
            arguments, _ throws(UsageError) in
            let words = try arguments.exactly(["<id>", "<text>"])
            return .send(.commentEdit(id: words[0], text: words[1]))
        },
        Command(name: "comment delete", synopsis: "comment delete <id>", summary: "remove a queued comment") {
            arguments, _ throws(UsageError) in
            .send(.commentDelete(id: try arguments.one("<id>")))
        },
    ]
}
