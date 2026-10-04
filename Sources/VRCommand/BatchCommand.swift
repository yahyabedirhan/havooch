import VRWire

/// `video-review batch send`: the queue sent as one batch, as Cmd+Enter
/// sends it.
public enum BatchCommand {
    public static let entry = CommandTable.Entry(
        name: "batch",
        summary: "send: send every queued comment as one batch to the listener",
        run: run
    )

    static let usageText = """
        usage: video-review batch send

          send   send every queued comment of the open video as one batch;
                 prints "sent b1 with 2 comments". A listener's `video-review
                 wait` gets it. With no listener, the batch waits for the
                 next one.

        Exits 1 when the app isn't running, another agent holds the lease,
        or nothing is queued.

        """

    static func parse(_ arguments: [String]) -> Result<ControlRequest, CommandResult> {
        if Arguments.asksForHelp(arguments) {
            return .failure(CommandResult(output: usageText))
        }
        guard let subcommand = arguments.first else {
            return .failure(CommandResult(error: usageText, status: CommandResult.usageStatus))
        }
        guard subcommand == "send" else {
            return .failure(.misread("video-review batch: unknown command `\(subcommand)`", usage: usageText))
        }
        if arguments.count > 1 {
            return .failure(.misread("video-review batch send: unexpected `\(arguments[1])`", usage: usageText))
        }
        return .success(.batchSend)
    }

    static func run(_ arguments: [String], context: CommandContext) -> CommandResult {
        context.send(parse(arguments))
    }
}
