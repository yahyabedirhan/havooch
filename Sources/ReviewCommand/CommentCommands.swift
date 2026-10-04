import Foundation
import ReviewWire

/// `video-review comment add | edit | delete`, `context set` and `batch send`.
enum CommentCommands {
    static let commands: [Command] = [
        Command(
            name: "comment add", synopsis: "comment add <text> [--at <time>] [--region x,y,w,h]",
            summary: "queue a comment at a time, or where the player is; --region is 0 to 1 from the frame's top-left corner",
            valuedOptions: ["--at", "--region"]
        ) { arguments, _ throws(UsageError) in
            let text = try arguments.one("<text>")
            var at: Double?
            if let time = arguments.options["--at"] {
                guard let seconds = TimeCode.seconds(time) else {
                    throw UsageError("`\(time)` isn't a time; write seconds (`90`, `12.5`) or `mm:ss` (`1:30`)")
                }
                at = seconds
            }
            var region: ControlRequest.Rectangle?
            if let numbers = arguments.options["--region"] {
                guard let rectangle = ControlRequest.Rectangle(numbers) else {
                    throw UsageError(
                        "`\(numbers)` isn't a region; write x,y,w,h as four numbers from 0 to 1, from the frame's top-left corner (`0.25,0.2,0.3,0.25`)"
                    )
                }
                region = rectangle
            }
            return .send(.commentAdd(text: text, at: at, region: region))
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
        Command(
            name: "context set", synopsis: "context set <text>",
            summary: "set the open video's context note for the agent; an empty text clears it"
        ) { arguments, _ throws(UsageError) in
            .send(.contextSet(text: try arguments.one("<text>")))
        },
        Command(name: "batch send", synopsis: "batch send", summary: "send every queued comment as one batch, which `wait` gets") {
            arguments, _ throws(UsageError) in
            try arguments.none()
            return .send(.batchSend)
        },
    ]
}
