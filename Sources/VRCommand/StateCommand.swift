import VRWire

/// `video-review state [--json]`: everything the app shows.
public enum StateCommand {
    public static let entry = CommandTable.Entry(
        name: "state",
        summary: "what the app shows: the video, the player's time, the comments, the batches, the listener, the lease",
        run: run
    )

    static let usageText = """
        usage: video-review state [--json]

          Prints what the app shows: the open video, the player's time and
          whether it plays, its comments, its batches, the listener and the
          lease. With --json, one JSON object: the player's time is at
          `player.time` and at the top-level `time`, the comments in time
          order at `comments`, the ids of those waiting to be sent at
          `queue`, the batches sent at `batches`, and whether a listener
          waits at `listener.presence` (absent, listening or working).

        Exits 1 when the app isn't running.

        """

    static func parse(_ arguments: [String]) -> Result<ControlRequest, CommandResult> {
        if Arguments.asksForHelp(arguments) {
            return .failure(CommandResult(output: usageText))
        }
        if let extra = arguments.first {
            return .failure(.misread("video-review state: unexpected `\(extra)`", usage: usageText))
        }
        return .success(.state)
    }

    static func run(_ arguments: [String], context: CommandContext) -> CommandResult {
        context.send(parse(arguments))
    }
}
