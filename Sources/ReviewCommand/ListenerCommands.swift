import Foundation
import ReviewWire

/// The listener's commands, which need no lease. `video-review wait
/// [--timeout <seconds>]` is a long-poll: it exits 0 with the next batch as
/// JSON, and the listener is present in the app while it's open. `ack`,
/// `status`, `reply` and `ask` answer in the player; `ask` is held until
/// the person answers, and exits 0 with the answer.
enum ListenerCommands {
    static let commands: [Command] = [
        Command(
            name: "wait", synopsis: "wait [--timeout <seconds>]",
            summary: "wait for the next batch and print it as JSON; exit 2 when --timeout runs out with none",
            valuedOptions: ["--timeout"]
        ) { arguments, _ throws(UsageError) in
            try arguments.none()
            guard let seconds = arguments.options["--timeout"] else { return .wait(timeout: nil) }
            guard let whole = Int(seconds), (0...ControlRequest.longestListen).contains(whole) else {
                throw UsageError("`--timeout` takes whole seconds from 0 to \(ControlRequest.longestListen), not `\(seconds)`")
            }
            return .wait(timeout: whole)
        },
        Command(
            name: "ack", synopsis: "ack <batch-id> [<text>]",
            summary: "say you have the batch: its comments turn acknowledged, and the text is a message for the full batch"
        ) { arguments, _ throws(UsageError) in
            guard let id = arguments.words.first else { throw UsageError("missing <batch-id>") }
            guard arguments.words.count <= 2 else { throw UsageError("unexpected `\(arguments.words[2])`") }
            return .send(.ack(batchID: id, text: arguments.words.count == 2 ? arguments.words[1] : nil))
        },
        Command(
            name: "status", synopsis: "status <comment-id> working|done|failed",
            summary: "say how far you are with a comment; its marker shows it"
        ) { arguments, _ throws(UsageError) in
            let words = try arguments.exactly(["<comment-id>", "working|done|failed"])
            guard let state = ControlRequest.Status(rawValue: words[1]) else {
                throw UsageError("`\(words[1])` isn't a status; write `working`, `done` or `failed`")
            }
            return .send(.status(commentID: words[0], state: state))
        },
        Command(
            name: "reply", synopsis: "reply <comment-id|batch-id> <text>",
            summary: "send a message on a comment's thread, or for the full batch with a batch id"
        ) { arguments, _ throws(UsageError) in
            let words = try arguments.exactly(["<comment-id|batch-id>", "<text>"])
            return .send(.reply(id: words[0], text: words[1]))
        },
        Command(
            name: "ask", synopsis: "ask <comment-id> <question> [--wait <seconds>]",
            summary: "ask a question on a comment and print the person's answer; exit 2 when --wait runs out with none",
            valuedOptions: ["--wait"]
        ) { arguments, _ throws(UsageError) in
            let words = try arguments.exactly(["<comment-id>", "<question>"])
            var wait: Int?
            if let seconds = arguments.options["--wait"] {
                guard let whole = Int(seconds), (0...ControlRequest.longestListen).contains(whole) else {
                    throw UsageError("`--wait` takes whole seconds from 0 to \(ControlRequest.longestListen), not `\(seconds)`")
                }
                wait = whole
            }
            return .send(.ask(commentID: words[0], question: words[1], waitSeconds: wait))
        },
    ]

    /// How long `wait` rests before it looks for the app again.
    static let retry: TimeInterval = 1

    /// Waits for the next batch, for `timeout` seconds or with no limit.
    /// The payload is JSON with or without `--json`. While the app isn't
    /// running, or quits, the command connects again each second, so a
    /// listener can start before the app and outlive its restart. Exit 0
    /// with the batch, 2 when the time ran out, 1 when the app refuses.
    static func wait(timeout: Int?, client: ControlClient, environment: CommandEnvironment) -> CommandResult {
        let deadline = timeout.map { environment.now().addingTimeInterval(TimeInterval($0)) }
        var client = client
        while true {
            // The app may have come back on other data: a demo, or the person's own.
            client.socket = ControlSocket.locate(support: SupportFolder.app(environment: environment.variables))
            // What's left of the time, rounded up: the app holds the request for it.
            let left = deadline.map { max(Int($0.timeIntervalSince(environment.now()).rounded(.up)), 0) }
            switch client.send(.wait(timeoutSeconds: left)) {
            case .success(let reply) where reply.timedOut == true:
                return CommandResult(exitCode: CommandResult.timedOutCode)
            case .failure(.notRunning):
                if let deadline, environment.now() >= deadline {
                    return CommandResult(exitCode: CommandResult.timedOutCode)
                }
                environment.pause(retry)
            case let answer:
                return VideoReviewCLI.result(of: answer)
            }
        }
    }
}
