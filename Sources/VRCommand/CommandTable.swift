import Foundation
import VRWire

/// The command's first words and what runs each: `standard` lists the
/// entries, `run` finds the one the arguments name. A library, so the table
/// tests without a process.
public struct CommandTable: Sendable {
    /// The table the `video-review` command runs: a new first word is one
    /// more entry here.
    public static var standard: CommandTable {
        var table = CommandTable()
        table.add([
            AppCommand.entry,
            ControlCommand.entry,
            StateCommand.entry,
            PlayerCommand.entry,
            CommentCommand.entry,
            BatchCommand.entry,
            ContextCommand.entry,
            ScreenshotCommand.entry,
            ListenerCommand.wait,
        ])
        return table
    }

    /// One first word: its line in the top-level help, and what runs the
    /// arguments after it.
    public struct Entry: Sendable {
        public var name: String
        public var summary: String
        public var run: @Sendable ([String], CommandContext) -> CommandResult

        public init(name: String, summary: String, run: @escaping @Sendable ([String], CommandContext) -> CommandResult) {
            self.name = name
            self.summary = summary
            self.run = run
        }
    }

    private var entries: [Entry] = []

    public init() {}

    public mutating func add(_ entries: [Entry]) {
        self.entries += entries
    }

    /// The top-level help: every entry's line.
    public var usageText: String {
        let width = (entries.map(\.name.count).max() ?? 0) + 2
        let lines = entries.map { "  " + $0.name.padding(toLength: width, withPad: " ", startingAt: 0) + $0.summary }
        return """
            usage: video-review <command> [--json]

            \(lines.joined(separator: "\n"))

            `video-review <command> --help` explains one command. --json prints
            one JSON object on one line instead of lines. Exit status: 0 done,
            1 refused or not running, 2 arguments that don't read, 3 a wait
            whose time ran out.

            """
    }

    /// Runs `arguments` (without the program's name). `--json` may stand
    /// anywhere; the first word picks the entry, which reads the rest.
    public func run(_ arguments: [String], environment: CommandEnvironment) -> CommandResult {
        let json = arguments.contains(Arguments.jsonFlag)
        let arguments = arguments.filter { $0 != Arguments.jsonFlag }
        guard let word = arguments.first else {
            return CommandResult(error: usageText, status: CommandResult.usageStatus)
        }
        switch word {
        case "--help", "-h", "help":
            return CommandResult(output: usageText)
        case "--version":
            return CommandResult(output: "video-review \(AppIdentity.versionText)\n")
        default:
            break
        }
        guard let entry = entries.first(where: { $0.name == word }) else {
            return .misread("video-review: unknown command `\(word)`", usage: usageText)
        }
        return entry.run(Array(arguments.dropFirst()), CommandContext(environment: environment, json: json))
    }
}
