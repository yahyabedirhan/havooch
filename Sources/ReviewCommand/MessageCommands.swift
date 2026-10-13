import Foundation
import ReviewWire

/// `havooch message add | edit | delete | send | state`: the queue of
/// messages on the open video, as the person writes, changes, removes and
/// sends them, under the lease; and the listener's state of a message,
/// with no lease.
enum MessageCommands {
    /// The listener's word for a message's state, which the top help lists
    /// with the listener's loop: its name lives here alone.
    static let state = Command(
        name: "message state", arguments: "<message-id> working|done|failed [<text>]",
        summary: "say a message is working, done or failed",
        description: "Its thread's pin shows the state. With working, the text says what you do now; done and failed "
            + "clear it. It needs no lease.",
        examples: ["m-f92cbb2a-1 working \"Rendering 0:14 to 0:21\"", "m-f92cbb2a-1 done"], role: .listener,
        brief: "<message-id> <state>", listing: .own(.feedback)
    ) { arguments, _ throws(UsageError) in
        let words = arguments.words
        guard words.count >= 1 else { throw UsageError("missing <message-id>") }
        guard words.count >= 2 else { throw UsageError("missing working|done|failed") }
        guard let state = ControlRequest.Status(rawValue: words[1]) else {
            throw UsageError("`\(words[1])` isn't a state; write `working`, `done` or `failed`")
        }
        // Only work in progress has a "now": done and failed clear the line.
        let most = state == .working ? 3 : 2
        guard words.count <= most else { throw UsageError("unexpected `\(words[most])`") }
        return .send(.status(messageID: words[0], state: state, text: words.count == 3 ? words[2] : nil))
    }

    static let group = CommandGroup(
        name: "message", summary: "queue, edit, delete and send messages, and say their state", section: .drive,
        commands: [
            Command(
                name: "message add", arguments: "<text> [--at <time>] [--region x,y,w,h] [--thread <thread>]",
                summary: "queue a message on a frame's thread",
                description: "The message goes on the thread of the frame at --at, else where the player is, or a new one; "
                    + "--thread takes a thread's id or number, 0 for General. --region is 0 to 1 from the frame's top-left corner.",
                examples: ["\"Too fast here\"", "\"This logo\" --at 0:12 --region 0.25,0.2,0.3,0.25", "\"And the end\" --thread 0"],
                role: .operator, valuedOptions: ["--at", "--region", "--thread"]
            ) { arguments, _ throws(UsageError) in
                let text = try arguments.one("<text>")
                var at: Double?
                if let time = arguments.options["--at"] {
                    guard let seconds = TimeCode.seconds(time) else {
                        throw UsageError("`\(time)` isn't a time; write seconds (`90`, `12.5`) or `m:ss` (`1:30`)")
                    }
                    at = seconds
                }
                let region = try MessageCommands.region(arguments)
                return .send(.commentAdd(text: text, at: at, region: region, thread: arguments.options["--thread"]))
            }.onAWindow(),
            Command(
                name: "message edit", arguments: "<message-id> <text>", summary: "change a queued message's text",
                examples: ["m-f92cbb2a-1 \"Slower here\""], role: .operator
            ) { arguments, _ throws(UsageError) in
                let words = try arguments.exactly(["<message-id>", "<text>"])
                return .send(.commentEdit(id: words[0], text: words[1]))
            }.onAWindow(),
            Command(
                name: "message delete", arguments: "<message-id>", summary: "remove a queued message",
                examples: ["m-f92cbb2a-1"], role: .operator
            ) { arguments, _ throws(UsageError) in
                .send(.commentDelete(id: try arguments.one("<message-id>")))
            }.onAWindow(),
            Command(
                name: "message send", summary: "send every queued message at once",
                description: "The listener's wait gets them as one send.", examples: ["", "--window w2"], role: .operator
            ) { arguments, _ throws(UsageError) in
                try arguments.none()
                return .send(.send)
            }.onAWindow(),
            state,
        ]
    )

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
