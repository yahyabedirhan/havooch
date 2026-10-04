import Foundation
import ReviewWire

/// The listener's commands, which need no lease. `video-review wait
/// [--timeout <seconds>]` is a long-poll: it exits 0 with the next batch as
/// JSON, and the listener is present in the app while it's open.
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
