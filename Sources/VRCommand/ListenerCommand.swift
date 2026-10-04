import VRWire

/// The listener's commands, which need no lease: a listener works beside
/// the person, it doesn't drive the app. `wait` gets a batch; `ack`,
/// `status`, `reply` and `ask` answer it inside the player.
public enum ListenerCommand {
    public static let wait = CommandTable.Entry(
        name: "wait",
        summary: "[--timeout <seconds>]: wait for the next batch and print it as JSON",
        run: runWait
    )

    static let waitUsage = """
        usage: video-review wait [--timeout <seconds>]

          Waits until the person sends a batch, then prints it as one JSON
          object: `batch` {id, sentAt}, `video` {path, contentHash, duration,
          title}, `context` (text or null) and `comments`, each with its id,
          time, text, keyframePath, region, cropPath and transcript. Images
          are PNG files; the paths are absolute. A batch sent before the wait
          started is printed at once.

            --timeout <seconds>   give up after that long (0 to 86400)

          The app shows a listener as present while a wait is open: run it
          again as soon as a batch came. No lease is needed.

        Exits 0 with a batch, 3 when the timeout ran out (nothing on standard
        output), 1 when the app isn't running or went away.

        """

    static func parseWait(_ arguments: [String]) -> Result<ControlRequest, CommandResult> {
        if Arguments.asksForHelp(arguments) {
            return .failure(CommandResult(output: waitUsage))
        }
        guard let first = arguments.first else { return .success(.wait(timeoutSeconds: nil)) }
        guard first == "--timeout" else {
            return .failure(.misread("video-review wait: unexpected `\(first)`", usage: waitUsage))
        }
        guard arguments.count >= 2 else {
            return .failure(.misread("video-review wait: --timeout needs a number of seconds", usage: waitUsage))
        }
        guard arguments.count == 2 else {
            return .failure(.misread("video-review wait: unexpected `\(arguments[2])`", usage: waitUsage))
        }
        guard let seconds = Int(arguments[1]), (0...ControlRequest.longestTimeout).contains(seconds) else {
            return .failure(.misread(
                "video-review wait: --timeout takes whole seconds from 0 to \(ControlRequest.longestTimeout), not `\(arguments[1])`",
                usage: waitUsage
            ))
        }
        return .success(.wait(timeoutSeconds: seconds))
    }

    static func runWait(_ arguments: [String], context: CommandContext) -> CommandResult {
        ranOut(context.send(parseWait(arguments)))
    }

    /// A long poll whose time ran out comes back done with nothing to print
    /// and a note: that, and only that, exits 3.
    static func ranOut(_ result: CommandResult) -> CommandResult {
        guard result.status == 0, result.output.isEmpty, !result.error.isEmpty else { return result }
        return CommandResult(error: result.error, status: CommandResult.timedOutStatus)
    }

    // MARK: - ack

    public static let ack = CommandTable.Entry(
        name: "ack",
        summary: "<batch-id> [<text>]: say you have the batch; its comments are acknowledged",
        run: { arguments, context in context.send(parseAck(arguments)) }
    )

    static let ackUsage = """
        usage: video-review ack <batch-id> [<text>]

          Tells the person you have the batch: each of its comments shows as
          acknowledged; prints "acknowledged b1". With <text>, the text shows
          as a message for the full batch.

        The text is one argument: quote it. No lease is needed. Exits 1 when
        the app isn't running or knows no such batch.

        """

    static func parseAck(_ arguments: [String]) -> Result<ControlRequest, CommandResult> {
        if Arguments.asksForHelp(arguments) {
            return .failure(CommandResult(output: ackUsage))
        }
        guard let id = arguments.first else {
            return .failure(.misread("video-review ack: missing <batch-id>", usage: ackUsage))
        }
        guard arguments.count <= 2 else {
            return .failure(.misread("video-review ack: unexpected `\(arguments[2])`; quote the text", usage: ackUsage))
        }
        if arguments.count == 2, Arguments.isBlank(arguments[1]) {
            return .failure(.misread("video-review ack: the text is empty; leave it out", usage: ackUsage))
        }
        return .success(.ack(batchID: id, text: arguments.count == 2 ? arguments[1] : nil))
    }

    // MARK: - status

    public static let status = CommandTable.Entry(
        name: "status",
        summary: "<comment-id> working|done|failed: show where the work on a comment is",
        run: { arguments, context in context.send(parseStatus(arguments)) }
    )

    static let statusUsage = """
        usage: video-review status <comment-id> working|done|failed

          Sets the comment's status, which shows on its marker and its card;
          prints "c1 is working". A status may skip forward (straight to
          done). done and failed are final: the comment can't change again.
          A batch whose comments are all done or failed is finished.

        No lease is needed. Exits 1 when the app isn't running, knows no such
        comment, or the comment can't move to that status.

        """

    static func parseStatus(_ arguments: [String]) -> Result<ControlRequest, CommandResult> {
        if Arguments.asksForHelp(arguments) {
            return .failure(CommandResult(output: statusUsage))
        }
        guard let id = arguments.first else {
            return .failure(.misread("video-review status: missing <comment-id>", usage: statusUsage))
        }
        guard arguments.count >= 2 else {
            return .failure(.misread("video-review status: missing working, done or failed", usage: statusUsage))
        }
        guard ControlRequest.statuses.contains(arguments[1]) else {
            return .failure(.misread(
                "video-review status: `\(arguments[1])` isn't a status; use working, done or failed", usage: statusUsage
            ))
        }
        guard arguments.count == 2 else {
            return .failure(.misread("video-review status: unexpected `\(arguments[2])`", usage: statusUsage))
        }
        return .success(.status(commentID: id, state: arguments[1]))
    }

    // MARK: - reply

    public static let reply = CommandTable.Entry(
        name: "reply",
        summary: "<comment-id|batch-id> <text>: write a message on a comment, or for a full batch",
        run: { arguments, context in context.send(parseReply(arguments)) }
    )

    static let replyUsage = """
        usage: video-review reply <comment-id|batch-id> <text>

          Writes a message in the thread of the comment, where the person
          reads it beside their feedback; prints "replied on c1". With a
          batch's id, the message is for the full batch. The person gets a
          brief notice.

        The text is one argument: quote it. No lease is needed. Exits 1 when
        the app isn't running or knows no such comment or batch.

        """

    static func parseReply(_ arguments: [String]) -> Result<ControlRequest, CommandResult> {
        if Arguments.asksForHelp(arguments) {
            return .failure(CommandResult(output: replyUsage))
        }
        switch Arguments.idAndText(arguments, id: "<comment-id|batch-id>", text: "<text>") {
        case .success(let (id, text)):
            return .success(.reply(id: id, text: text))
        case .failure(let line):
            return .failure(.misread("video-review reply: \(line.reason)", usage: replyUsage))
        }
    }

    // MARK: - ask

    public static let ask = CommandTable.Entry(
        name: "ask",
        summary: "<comment-id> <question> [--wait <seconds>]: ask the person and print their answer",
        run: { arguments, context in ranOut(context.send(parseAsk(arguments))) }
    )

    static let askUsage = """
        usage: video-review ask <comment-id> <question> [--wait <seconds>]

          Writes a question in the comment's thread and waits for the person
          to answer it in the player, then prints the answer's text. With
          --json: {commentId, question, answer, answeredAt}.

            --wait <seconds>   give up after that long (0 to 86400); the
                               question stays open

          One question at a time on a comment. After a timeout, ask again in
          the same words to go on waiting for the same question. An answer
          that came after the timeout is printed at once by the next ask on
          that comment, once.

        The question is one argument: quote it. No lease is needed. Exits 0
        with the answer, 3 when the wait ran out (nothing on standard
        output), 1 when the app isn't running, went away or refuses.

        """

    static func parseAsk(_ arguments: [String]) -> Result<ControlRequest, CommandResult> {
        if Arguments.asksForHelp(arguments) {
            return .failure(CommandResult(output: askUsage))
        }
        var words: [String] = []
        var seconds: Int?
        var rest = arguments[...]
        while let argument = rest.popFirst() {
            switch argument {
            case "--wait":
                guard let value = rest.popFirst() else {
                    return .failure(.misread("video-review ask: --wait needs a number of seconds", usage: askUsage))
                }
                guard let number = Int(value), (0...ControlRequest.longestTimeout).contains(number) else {
                    return .failure(.misread(
                        "video-review ask: --wait takes whole seconds from 0 to \(ControlRequest.longestTimeout), not `\(value)`",
                        usage: askUsage
                    ))
                }
                seconds = number
            case let option where option.hasPrefix("--") && option.count > 2:
                return .failure(.misread("video-review ask: unknown option `\(option)`", usage: askUsage))
            default:
                words.append(argument)
            }
        }
        switch Arguments.idAndText(words, id: "<comment-id>", text: "<question>") {
        case .success(let (id, question)):
            return .success(.ask(commentID: id, question: question, waitSeconds: seconds))
        case .failure(let line):
            return .failure(.misread("video-review ask: \(line.reason)", usage: askUsage))
        }
    }
}
