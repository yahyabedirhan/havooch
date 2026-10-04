import Foundation
import VRWire

/// `video-review player open | play | pause | seek`: the player driven as a
/// person drives it.
public enum PlayerCommand {
    public static let entry = CommandTable.Entry(
        name: "player",
        summary: "open <path> | play | pause | seek <time>: drive the player",
        run: run
    )

    static let usageText = """
        usage: video-review player open <path> | play | pause | seek <time>

          open <path>   open a local mp4, mov or m4v file, paused at its start.
                        A relative path is relative to this folder.
          play          play from where the player is
          pause         pause
          seek <time>   move to a time, exactly: seconds (10, 10.5), mm:ss
                        (0:10, 1:02.5) or h:mm:ss. A time outside the video is
                        refused.

        Exits 1 when the app isn't running or refuses.

        """

    /// Reads the arguments after `player`, a relative path resolved against
    /// `workingDirectory` since the app runs in another folder.
    static func parse(_ arguments: [String], workingDirectory: URL) -> Result<ControlRequest, CommandResult> {
        if Arguments.asksForHelp(arguments) {
            return .failure(CommandResult(output: usageText))
        }
        guard let subcommand = arguments.first else {
            return .failure(CommandResult(error: usageText, status: CommandResult.usageStatus))
        }
        let rest = Array(arguments.dropFirst())
        switch (subcommand, rest.count) {
        case ("open", 1):
            return .success(.playerOpen(path: Arguments.absolute(rest[0], in: workingDirectory).path))
        case ("open", 0):
            return .failure(misread("video-review player open: missing <path>"))
        case ("play", 0):
            return .success(.playerPlay)
        case ("pause", 0):
            return .success(.playerPause)
        case ("seek", 1):
            guard let seconds = Arguments.time(rest[0]) else {
                return .failure(misread("video-review player seek: `\(rest[0])` isn't a time; use seconds, mm:ss or h:mm:ss"))
            }
            return .success(.playerSeek(seconds: seconds))
        case ("seek", 0):
            return .failure(misread("video-review player seek: missing <time>"))
        case ("open", _), ("seek", _):
            return .failure(misread("video-review player \(subcommand): unexpected `\(rest[1])`"))
        case ("play", _), ("pause", _):
            return .failure(misread("video-review player \(subcommand): unexpected `\(rest[0])`"))
        default:
            return .failure(misread("video-review player: unknown command `\(subcommand)`"))
        }
    }

    private static func misread(_ line: String) -> CommandResult {
        .misread(line, usage: usageText)
    }

    static func run(_ arguments: [String], context: CommandContext) -> CommandResult {
        context.send(parse(arguments, workingDirectory: context.workingDirectory))
    }
}
