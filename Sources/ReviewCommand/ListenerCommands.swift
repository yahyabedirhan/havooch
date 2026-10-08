import Foundation
import ReviewWire

/// The listener's commands, which need no lease. `havooch wait [--video
/// <path>] [--timeout <seconds>]` is a long-poll: it exits 0 with the next
/// send of one video as JSON, and that video's window shows the listener
/// while it's open. `ack`, `status`, `reply` and `ask` answer in the
/// player, on the video their id names; `ask` is held until the person
/// answers, and exits 0 with the answer.
enum ListenerCommands {
    static let commands: [Command] = [
        Command(
            name: "wait", synopsis: "wait [--video <path>] [--timeout <seconds>]",
            summary: "wait for the next send of the video at <path> (else the key window's) and print it as JSON; exit 2 when --timeout runs out with none",
            valuedOptions: ["--timeout", "--video"]
        ) { arguments, environment throws(UsageError) in
            try arguments.none()
            // Made absolute here: the app runs in another folder.
            let video = arguments.options["--video"].map {
                URL(fileURLWithPath: $0, relativeTo: environment.workingDirectory).standardizedFileURL
            }
            guard let seconds = arguments.options["--timeout"] else { return .wait(timeout: nil, video: video) }
            guard let whole = Int(seconds), (0...ControlRequest.longestListen).contains(whole) else {
                throw UsageError("`--timeout` takes whole seconds from 0 to \(ControlRequest.longestListen), not `\(seconds)`")
            }
            return .wait(timeout: whole, video: video)
        },
        Command(
            name: "ack", synopsis: "ack <send-id> [<text>]",
            summary: "say you have the send: its messages turn acknowledged, and the text goes on the General thread"
        ) { arguments, _ throws(UsageError) in
            guard let id = arguments.words.first else { throw UsageError("missing <send-id>") }
            guard arguments.words.count <= 2 else { throw UsageError("unexpected `\(arguments.words[2])`") }
            return .send(.ack(sendID: id, text: arguments.words.count == 2 ? arguments.words[1] : nil))
        },
        Command(
            name: "status", synopsis: "status <message-id> working|done|failed [<text>]",
            summary: "say how far you are with a message; its thread's pin shows it, and the text with working what you do now"
        ) { arguments, _ throws(UsageError) in
            let words = arguments.words
            guard words.count >= 1 else { throw UsageError("missing <message-id>") }
            guard words.count >= 2 else { throw UsageError("missing working|done|failed") }
            guard let state = ControlRequest.Status(rawValue: words[1]) else {
                throw UsageError("`\(words[1])` isn't a status; write `working`, `done` or `failed`")
            }
            // Only work in progress has a "now": done and failed clear the line.
            let most = state == .working ? 3 : 2
            guard words.count <= most else { throw UsageError("unexpected `\(words[most])`") }
            return .send(.status(messageID: words[0], state: state, text: words.count == 3 ? words[2] : nil))
        },
        Command(
            name: "reply", synopsis: "reply <thread> <text>",
            summary: "send a message on a thread: its id, or a number of the open video (0 for General)"
        ) { arguments, _ throws(UsageError) in
            let words = try arguments.exactly(["<thread>", "<text>"])
            return .send(.reply(thread: words[0], text: words[1]))
        },
        Command(
            name: "ask", synopsis: "ask <thread> <question> [--choice <text>]... [--wait <seconds>]",
            summary: "ask a question on a thread and print the person's answer; each --choice is a quick reply the person can click; exit 2 when --wait runs out with none",
            valuedOptions: ["--wait", "--choice"]
        ) { arguments, _ throws(UsageError) in
            let words = try arguments.exactly(["<thread>", "<question>"])
            var wait: Int?
            if let seconds = arguments.options["--wait"] {
                guard let whole = Int(seconds), (0...ControlRequest.longestListen).contains(whole) else {
                    throw UsageError("`--wait` takes whole seconds from 0 to \(ControlRequest.longestListen), not `\(seconds)`")
                }
                wait = whole
            }
            let choices = arguments.repeated["--choice"] ?? []
            return .send(.ask(thread: words[0], question: words[1], waitSeconds: wait, choices: choices))
        },
    ]

    /// How long `wait` rests before it looks for the app again.
    static let retry: TimeInterval = 1

    /// Waits for the next send of the video at `video` (else the key
    /// window's), for `timeout` seconds or with no limit.
    /// The payload is JSON with or without `--json`. While the app isn't
    /// running, or quits, the command connects again each second, so a
    /// listener can start before the app and outlive its restart. Exit 0
    /// with the send, 2 when the time ran out, 1 when the app refuses.
    static func wait(timeout: Int?, video: URL? = nil, client: ControlClient, environment: CommandEnvironment) -> CommandResult {
        let deadline = timeout.map { environment.now().addingTimeInterval(TimeInterval($0)) }
        var client = client
        while true {
            // The app may have come back on other data: a demo, or the person's own.
            client.socket = ControlSocket.locate(support: SupportFolder.app(environment: environment.variables))
            // What's left of the time, rounded up: the app holds the request for it.
            let left = deadline.map { max(Int($0.timeIntervalSince(environment.now()).rounded(.up)), 0) }
            switch client.send(.wait(timeoutSeconds: left, video: video?.path)) {
            case .success(let reply) where reply.timedOut == true:
                return CommandResult(exitCode: CommandResult.timedOutCode)
            case .failure(.notRunning):
                if let deadline, environment.now() >= deadline {
                    return CommandResult(exitCode: CommandResult.timedOutCode)
                }
                environment.pause(retry)
            case let answer:
                return HavoochCLI.result(of: answer)
            }
        }
    }
}
