import VRWire

/// The listener's commands, which need no lease: a listener works beside
/// the person, it doesn't drive the app. `wait` is the first of them.
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
}
