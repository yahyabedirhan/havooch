import VRWire

/// `video-review control take [--wait <seconds>] | release`: holding and
/// giving up the lease on purpose. Both are free commands: the app decides
/// them by the lease's own rules.
public enum ControlCommand {
    public static let entry = CommandTable.Entry(
        name: "control",
        summary: "take [--wait <seconds>] | release: hold the app for a longer run, or give it up",
        run: run
    )

    static let usageText = """
        usage: video-review control take [--wait <seconds>] | release

          take      hold video-review until 5 minutes after you took it, so
                    other agents' operator commands are refused meanwhile;
                    prints "you hold video-review until <HH:mm:ss>"
                    --wait <seconds>: while another agent holds it, wait in
                    line, first come first served, up to that long (0 to
                    3600)
          release   give video-review up, so the next agent in line gets it;
                    does nothing when you don't hold it

        Without take, your first operator command takes the lease and each
        later one renews it for a minute. To send every command as one
        holder <k>, export VIDEO_REVIEW_CONTROL_KEY=<k> for the run.

        Each exits 1 when the app isn't running; take also when another agent
        holds it, or still holds it once the wait runs out.

        """

    /// Reads the arguments after `control`. `--help` is the usage on
    /// standard output; anything that doesn't read is the usage on standard
    /// error, exit 2.
    static func parse(_ arguments: [String]) -> Result<ControlRequest, CommandResult> {
        if Arguments.asksForHelp(arguments) {
            return .failure(CommandResult(output: usageText))
        }
        guard let subcommand = arguments.first else {
            return .failure(CommandResult(error: usageText, status: CommandResult.usageStatus))
        }
        let rest = Array(arguments.dropFirst())
        switch (subcommand, rest.first) {
        case ("take", nil):
            return .success(.controlTake(waitSeconds: nil))
        case ("take", "--wait"?):
            guard rest.count >= 2 else {
                return .failure(misread("video-review control take: --wait needs a number of seconds"))
            }
            guard rest.count == 2 else {
                return .failure(misread("video-review control take: unexpected `\(rest[2])`"))
            }
            guard let seconds = Int(rest[1]), (0...ControlRequest.longestWait).contains(seconds) else {
                return .failure(misread(
                    "video-review control take: --wait takes whole seconds from 0 to \(ControlRequest.longestWait), not `\(rest[1])`"
                ))
            }
            return .success(.controlTake(waitSeconds: seconds))
        case ("release", nil):
            return .success(.controlRelease)
        case ("take", let extra?), ("release", let extra?):
            return .failure(misread("video-review control \(subcommand): unexpected `\(extra)`"))
        default:
            return .failure(misread("video-review control: unknown command `\(subcommand)`"))
        }
    }

    private static func misread(_ line: String) -> CommandResult {
        .misread(line, usage: usageText)
    }

    static func run(_ arguments: [String], context: CommandContext) -> CommandResult {
        context.send(parse(arguments))
    }
}
