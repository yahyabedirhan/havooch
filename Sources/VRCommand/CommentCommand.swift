import Foundation
import VRWire

/// `video-review comment add | edit | delete`: the queue changed as a person
/// changes it.
public enum CommentCommand {
    public static let entry = CommandTable.Entry(
        name: "comment",
        summary: "add <text> [--at <time>] | edit <id> <text> | delete <id>: change the queue",
        run: run
    )

    static let usageText = """
        usage: video-review comment add <text> [--at <time>] | edit <id> <text> | delete <id>

          add <text>         queue a comment at the player's time, with the
                             frame there as its keyframe. The video is paused.
            --at <time>      at this time instead; the player moves there.
                             Seconds (10, 10.5), mm:ss (0:10) or h:mm:ss.
          edit <id> <text>   replace a queued comment's text
          delete <id>        take a queued comment out

        The text is one argument: quote it. A comment that was sent can't be
        edited or deleted. Exits 1 when the app isn't running or refuses.

        """

    static func parse(_ arguments: [String]) -> Result<ControlRequest, CommandResult> {
        if Arguments.asksForHelp(arguments) {
            return .failure(CommandResult(output: usageText))
        }
        guard let subcommand = arguments.first else {
            return .failure(CommandResult(error: usageText, status: CommandResult.usageStatus))
        }
        let rest = Array(arguments.dropFirst())
        switch subcommand {
        case "add": return add(rest)
        case "edit": return edit(rest)
        case "delete": return delete(rest)
        default: return .failure(misread("video-review comment: unknown command `\(subcommand)`"))
        }
    }

    private static func add(_ arguments: [String]) -> Result<ControlRequest, CommandResult> {
        var text: String?
        var at: Double?
        var rest = arguments[...]
        while let argument = rest.popFirst() {
            switch argument {
            case "--at":
                guard let value = rest.popFirst() else {
                    return .failure(misread("video-review comment add: --at needs a time"))
                }
                guard let seconds = Arguments.time(value) else {
                    return .failure(misread("video-review comment add: `\(value)` isn't a time; use seconds, mm:ss or h:mm:ss"))
                }
                at = seconds
            case let option where option.hasPrefix("--") && option.count > 2:
                return .failure(misread("video-review comment add: unknown option `\(option)`"))
            case let words where text == nil:
                text = words
            case let extra:
                return .failure(misread("video-review comment add: unexpected `\(extra)`; quote the text"))
            }
        }
        guard let text, !isBlank(text) else {
            return .failure(misread("video-review comment add: missing <text>"))
        }
        return .success(.commentAdd(text: text, at: at))
    }

    private static func edit(_ arguments: [String]) -> Result<ControlRequest, CommandResult> {
        guard let id = arguments.first else {
            return .failure(misread("video-review comment edit: missing <id>"))
        }
        guard arguments.count >= 2, !isBlank(arguments[1]) else {
            return .failure(misread("video-review comment edit: missing <text>"))
        }
        guard arguments.count == 2 else {
            return .failure(misread("video-review comment edit: unexpected `\(arguments[2])`; quote the text"))
        }
        return .success(.commentEdit(id: id, text: arguments[1]))
    }

    private static func delete(_ arguments: [String]) -> Result<ControlRequest, CommandResult> {
        guard let id = arguments.first else {
            return .failure(misread("video-review comment delete: missing <id>"))
        }
        guard arguments.count == 1 else {
            return .failure(misread("video-review comment delete: unexpected `\(arguments[1])`"))
        }
        return .success(.commentDelete(id: id))
    }

    private static func isBlank(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func misread(_ line: String) -> CommandResult {
        .misread(line, usage: usageText)
    }

    static func run(_ arguments: [String], context: CommandContext) -> CommandResult {
        context.send(parse(arguments))
    }
}
