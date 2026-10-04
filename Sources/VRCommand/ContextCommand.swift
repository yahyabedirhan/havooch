import VRWire

/// `video-review context set <text>`: the open video's note written as a
/// person writes it in the window.
public enum ContextCommand {
    public static let entry = CommandTable.Entry(
        name: "context",
        summary: "set <text>: write the open video's note for the listener",
        run: run
    )

    static let usageText = """
        usage: video-review context set <text>

          set <text>   replace the open video's note; prints "context note
                       set". An empty text ("") takes the note away.

        The listener gets a video's context with the first batch of its
        session, and again when the context changed: the text of
        <video name>.context.md, else context.md, in the video's folder,
        then the note under "## Reviewer's note". `state --json` names the
        file and the note at `context`.

        The text is one argument: quote it. Exits 1 when the app isn't
        running, another agent holds the lease, or no video is open.

        """

    static func parse(_ arguments: [String]) -> Result<ControlRequest, CommandResult> {
        if Arguments.asksForHelp(arguments) {
            return .failure(CommandResult(output: usageText))
        }
        guard let subcommand = arguments.first else {
            return .failure(CommandResult(error: usageText, status: CommandResult.usageStatus))
        }
        guard subcommand == "set" else {
            return .failure(.misread("video-review context: unknown command `\(subcommand)`", usage: usageText))
        }
        guard arguments.count >= 2 else {
            return .failure(.misread("video-review context set: missing <text>", usage: usageText))
        }
        guard arguments.count == 2 else {
            return .failure(.misread("video-review context set: unexpected `\(arguments[2])`; quote the text", usage: usageText))
        }
        return .success(.contextSet(text: arguments[1]))
    }

    static func run(_ arguments: [String], context: CommandContext) -> CommandResult {
        context.send(parse(arguments))
    }
}
