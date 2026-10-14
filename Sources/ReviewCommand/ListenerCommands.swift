import Foundation
import ReviewWire

enum ListenerCommands {
    static let group = CommandGroup(
        name: nil, summary: "get feedback: wait for the person's sends and answer them", section: .feedback,
        commands: [OpenCommand.command, wait, ack, reply, ask]
    )

    private static let wait = Command(
        name: "wait", arguments: "[--video <path> | --project <slug>] [--timeout <seconds>]",
        summary: "wait for the person's next send and print it",
        description: "It waits for a send of the video at <path>, of the project <slug>, else of the key window's video, "
            + "and prints it as JSON. The window shows the listener while it waits. While the app isn't running, it "
            + "connects again each second.",
        examples: ["", "--timeout 600", "--project launch-video"], role: .listener,
        exitCodes: "124 when --timeout runs out with no send.",
        valuedOptions: ["--timeout", "--video", "--project"]
    ) { arguments, environment throws(UsageError) in
        try arguments.none()
        let video = arguments.options["--video"].map {
            URL(fileURLWithPath: $0, relativeTo: environment.workingDirectory).standardizedFileURL
        }
        let project = arguments.options["--project"]
        if video != nil, project != nil { throw UsageError("give --video or --project, not both") }
        guard let seconds = arguments.options["--timeout"] else { return .wait(timeout: nil, video: video, project: project) }
        guard let whole = Int(seconds), (0...ControlRequest.longestListen).contains(whole) else {
            throw UsageError("`--timeout` takes whole seconds from 0 to \(ControlRequest.longestListen), not `\(seconds)`")
        }
        return .wait(timeout: whole, video: video, project: project)
    }

    private static let ack = Command(
        name: "ack", arguments: "<send-id> [<text>]",
        summary: "say you have a send",
        description: "Its messages turn acknowledged, and the text goes on the General thread.",
        examples: ["s-f92cbb2a-1", "s-f92cbb2a-1 \"On it: three changes\""], role: .listener
    ) { arguments, _ throws(UsageError) in
        guard let id = arguments.words.first else { throw UsageError("missing <send-id>") }
        guard arguments.words.count <= 2 else { throw UsageError("unexpected `\(arguments.words[2])`") }
        return .send(.ack(sendID: id, text: arguments.words.count == 2 ? arguments.words[1] : nil))
    }

    private static let reply = Command(
        name: "reply", arguments: "<thread> <text>",
        summary: "send a message on a thread",
        description: "The thread is its id, or its number in the open video, 0 for General.",
        examples: ["2 \"Slowed the intro down\"", "t-f92cbb2a-1 \"Done, see v3\""], role: .listener
    ) { arguments, _ throws(UsageError) in
        let words = try arguments.exactly(["<thread>", "<text>"])
        return .send(.reply(thread: words[0], text: words[1]))
    }

    private static let ask = Command(
        name: "ask", arguments: "<thread> <question> [--choice <text>]... [--timeout <seconds>]",
        summary: "ask a question on a thread and print the answer",
        description: "Each --choice is a quick reply the person can click. Without --timeout it waits with no limit.",
        examples: ["1 \"Which part?\"", "1 \"Keep the music?\" --choice Yes --choice No --timeout 600"], role: .listener,
        exitCodes: "124 when --timeout runs out with no answer.",
        valuedOptions: ["--timeout", "--choice"]
    ) { arguments, _ throws(UsageError) in
        let words = try arguments.exactly(["<thread>", "<question>"])
        var wait: Int?
        if let seconds = arguments.options["--timeout"] {
            guard let whole = Int(seconds), (0...ControlRequest.longestListen).contains(whole) else {
                throw UsageError("`--timeout` takes whole seconds from 0 to \(ControlRequest.longestListen), not `\(seconds)`")
            }
            wait = whole
        }
        let choices = arguments.repeated["--choice"] ?? []
        return .send(.ask(thread: words[0], question: words[1], waitSeconds: wait, choices: choices))
    }

    static let retry: TimeInterval = 1

    static func wait(
        timeout: Int?, video: URL? = nil, project: String? = nil, client: ControlClient, environment: CommandEnvironment
    ) -> CommandResult {
        let deadline = timeout.map { environment.now().addingTimeInterval(TimeInterval($0)) }
        var client = client
        while true {
            client.socket = ControlSocket.locate(support: SupportFolder.app(environment: environment.variables))
            let left = deadline.map { max(Int($0.timeIntervalSince(environment.now()).rounded(.up)), 0) }
            switch client.send(.wait(timeoutSeconds: left, video: video?.path, project: project)) {
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
