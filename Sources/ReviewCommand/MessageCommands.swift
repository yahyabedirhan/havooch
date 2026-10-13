import Foundation
import ReviewWire

/// `havooch message add | edit | delete | send`: the queue of messages on
/// the open video, as the person writes, changes, removes and sends them.
enum MessageCommands {
    static let commands: [Command] = [
        Command(
            name: "message add", synopsis: "message add <text> [--at <time>] [--region x,y,w,h] [--thread <thread>]",
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
            let region = try MessageCommands.region(arguments)
            return .send(.commentAdd(text: text, at: at, region: region, thread: arguments.options["--thread"]))
        },
        Command(name: "message edit", synopsis: "message edit <message-id> <text>", summary: "change a queued message's text") {
            arguments, _ throws(UsageError) in
            let words = try arguments.exactly(["<message-id>", "<text>"])
            return .send(.commentEdit(id: words[0], text: words[1]))
        },
        Command(name: "message delete", synopsis: "message delete <message-id>", summary: "remove a queued message") {
            arguments, _ throws(UsageError) in
            .send(.commentDelete(id: try arguments.one("<message-id>")))
        },
        Command(name: "message send", synopsis: "message send", summary: "send every queued message at once, which `wait` gets") {
            arguments, _ throws(UsageError) in
            try arguments.none()
            return .send(.send)
        },
    ]

    /// The `--region x,y,w,h` written, if any: a message's, the popover's
    /// or the composer's region on the frame.
    static func region(_ arguments: Arguments) throws(UsageError) -> ControlRequest.Rectangle? {
        guard let numbers = arguments.options["--region"] else { return nil }
        guard let rectangle = ControlRequest.Rectangle(numbers) else {
            throw UsageError(
                "`\(numbers)` isn't a region; write x,y,w,h as four numbers from 0 to 1, from the frame's top-left corner (`0.25,0.2,0.3,0.25`)"
            )
        }
        return rectangle
    }
}
