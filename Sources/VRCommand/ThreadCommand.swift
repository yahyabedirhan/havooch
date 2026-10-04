import Foundation
import VRWire

/// `video-review thread answer`: the person's answer to an agent's question,
/// given as the answer box in the comment's card gives it.
public enum ThreadCommand {
    public static let entry = CommandTable.Entry(
        name: "thread",
        summary: "answer <comment-id> <text>: answer the agent's question on a comment",
        run: run
    )

    static let usageText = """
        usage: video-review thread answer <comment-id> <text>

          answer <comment-id> <text>   answer the question open on the comment,
                                       as the person does in its card; prints
                                       "answered c1". The listener's `video-review
                                       ask` gets the text.

        The text is one argument: quote it. Exits 1 when the app isn't
        running, another agent holds the lease, or the comment has no
        question to answer.

        """

    static func parse(_ arguments: [String]) -> Result<ControlRequest, CommandResult> {
        if Arguments.asksForHelp(arguments) {
            return .failure(CommandResult(output: usageText))
        }
        guard let subcommand = arguments.first else {
            return .failure(CommandResult(error: usageText, status: CommandResult.usageStatus))
        }
        guard subcommand == "answer" else {
            return .failure(.misread("video-review thread: unknown command `\(subcommand)`", usage: usageText))
        }
        switch Arguments.idAndText(Array(arguments.dropFirst()), id: "<comment-id>", text: "<text>") {
        case .success(let (id, text)):
            return .success(.threadAnswer(commentID: id, text: text))
        case .failure(let line):
            return .failure(.misread("video-review thread answer: \(line.reason)", usage: usageText))
        }
    }

    static func run(_ arguments: [String], context: CommandContext) -> CommandResult {
        context.send(parse(arguments))
    }
}
