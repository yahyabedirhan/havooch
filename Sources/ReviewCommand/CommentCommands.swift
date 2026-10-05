import Foundation
import ReviewWire

/// `video-review comment add | open | compose | edit | delete`, `context set`, `send` and
/// `thread answer`.
enum CommentCommands {
    static let commands: [Command] = [
        Command(
            name: "comment add", synopsis: "comment add <text> [--at <time>] [--region x,y,w,h] [--thread <thread>]",
            summary: "queue a message on the thread of a frame (or a new one), at a time or where the player is; --region is 0 to 1 from the frame's top-left corner; --thread takes a thread id or number, 0 for General",
            valuedOptions: ["--at", "--region", "--thread"]
        ) { arguments, _ throws(UsageError) in
            let text = try arguments.one("<text>")
            var at: Double?
            if let time = arguments.options["--at"] {
                guard let seconds = TimeCode.seconds(time) else {
                    throw UsageError("`\(time)` isn't a time; write seconds (`90`, `12.5`) or `mm:ss` (`1:30`)")
                }
                at = seconds
            }
            let region = try CommentCommands.region(arguments)
            return .send(.commentAdd(text: text, at: at, region: region, thread: arguments.options["--thread"]))
        },
        Command(
            name: "comment open", synopsis: "comment open [<text>] [--region x,y,w,h]",
            summary: "open the comment popover at the player's frame, as C or a drawn rectangle does, with <text> in its field; a seek or play then closes it by the popover's rules",
            valuedOptions: ["--region"]
        ) { arguments, _ throws(UsageError) in
            guard arguments.words.count <= 1 else { throw UsageError("unexpected `\(arguments.words[1])`") }
            return .send(.commentOpen(text: arguments.words.first ?? "", region: try CommentCommands.region(arguments)))
        },
        Command(
            name: "comment compose", synopsis: "comment compose [<text>] [--region x,y,w,h] [--general]",
            summary: "put <text> in the composer at the sidebar's foot, as the person types it, for the target it shows; --region adds a region chip on the player's frame; --general turns the General toggle on in the thread list",
            valuedOptions: ["--region"], flags: ["--general"]
        ) { arguments, _ throws(UsageError) in
            guard arguments.words.count <= 1 else { throw UsageError("unexpected `\(arguments.words[1])`") }
            return .send(
                .commentCompose(
                    text: arguments.words.first ?? "", region: try CommentCommands.region(arguments),
                    general: arguments.flags.contains("--general")
                )
            )
        },
        Command(name: "comment edit", synopsis: "comment edit <message-id> <text>", summary: "change a queued message's text") {
            arguments, _ throws(UsageError) in
            let words = try arguments.exactly(["<message-id>", "<text>"])
            return .send(.commentEdit(id: words[0], text: words[1]))
        },
        Command(name: "comment delete", synopsis: "comment delete <message-id>", summary: "remove a queued message") {
            arguments, _ throws(UsageError) in
            .send(.commentDelete(id: try arguments.one("<message-id>")))
        },
        Command(
            name: "context set", synopsis: "context set <text>",
            summary: "set the open video's context note for the agent; an empty text clears it"
        ) { arguments, _ throws(UsageError) in
            .send(.contextSet(text: try arguments.one("<text>")))
        },
        Command(name: "send", synopsis: "send", summary: "send every queued message at once, which `wait` gets") {
            arguments, _ throws(UsageError) in
            try arguments.none()
            return .send(.send)
        },
        Command(
            name: "thread answer", synopsis: "thread answer <thread> <text>",
            summary: "answer the agent's open question on a thread (an id, or a number of the open video), as the person does"
        ) { arguments, _ throws(UsageError) in
            let words = try arguments.exactly(["<thread>", "<text>"])
            return .send(.threadAnswer(thread: words[0], text: words[1]))
        },
        Command(
            name: "thread open", synopsis: "thread open <thread> [--frame x,y,w,h]",
            summary: "open a thread's popover on its frame, as a click on its pin or its badge does; --frame first keeps the popover there, 0 to 1 of the video area from its top-left corner, as a drag and a resize leave it",
            valuedOptions: ["--frame"]
        ) { arguments, _ throws(UsageError) in
            let thread = try arguments.one("<thread>")
            var frame: ControlRequest.Rectangle?
            if let numbers = arguments.options["--frame"] {
                guard let rectangle = ControlRequest.Rectangle(numbers) else {
                    throw UsageError(
                        "`\(numbers)` isn't a frame; write x,y,w,h as four numbers from 0 to 1, from the video area's top-left corner (`0.55,0.1,0.4,0.5`)"
                    )
                }
                frame = rectangle
            }
            return .send(.threadOpen(thread: thread, frame: frame))
        },
        Command(
            name: "thread show", synopsis: "thread show <thread>",
            summary: "show a thread's view (an id, or a number of the open video) in the sidebar, as a click on its row does: the player pauses on its frame"
        ) { arguments, _ throws(UsageError) in
            .send(.threadShow(thread: try arguments.one("<thread>")))
        },
        Command(
            name: "thread list", synopsis: "thread list",
            summary: "show the thread list in the sidebar, as Back in a thread view does"
        ) { arguments, _ throws(UsageError) in
            try arguments.none()
            return .send(.threadList)
        },
    ]

    /// The `--region x,y,w,h` written, if any.
    private static func region(_ arguments: Arguments) throws(UsageError) -> ControlRequest.Rectangle? {
        guard let numbers = arguments.options["--region"] else { return nil }
        guard let rectangle = ControlRequest.Rectangle(numbers) else {
            throw UsageError(
                "`\(numbers)` isn't a region; write x,y,w,h as four numbers from 0 to 1, from the frame's top-left corner (`0.25,0.2,0.3,0.25`)"
            )
        }
        return rectangle
    }
}
