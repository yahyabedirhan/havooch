import Foundation
import ReviewWire

/// What a command line asks for.
enum Invocation: Equatable, Sendable {
    /// A request the running app answers.
    case send(ControlRequest, window: String? = nil)
    /// `app status`: answered without the app when it isn't running.
    case appStatus
    /// `app open`: launch the app unless it runs on the data asked for, on
    /// the demo's support folder when there is one.
    case appOpen(demo: URL?)
    /// `app quit`: ask the app to quit, then wait until it's gone.
    case appQuit
    /// `open <path>`: the video at the absolute `file` opened in front,
    /// with the app launched first when it doesn't run.
    case open(URL)
    /// `wait`: hold a request until a send is made, for `timeout` seconds
    /// or with no limit, connecting again while the app isn't running.
    case wait(timeout: Int?)
    /// `config path`: answered without the app.
    case configPath
    /// `config check`: answered without the app.
    case configCheck
}

/// Arguments that don't read, as one line.
struct UsageError: Error, Equatable {
    var message: String

    init(_ message: String) {
        self.message = message
    }
}

/// A command's arguments, split into the words and the `--options`.
struct Arguments: Equatable {
    var words: [String] = []
    /// Each valued option written, with its value; the last one when it's
    /// written more than once.
    var options: [String: String] = [:]
    /// Every value of each valued option, in the order written: a
    /// repeatable option such as `ask --choice` reads all of them.
    var repeated: [String: [String]] = [:]
    /// The `--flags` written: options with no value.
    var flags: Set<String> = []

    /// Reads `raw`; `valued` names the options the command takes, each
    /// with a value after it, and `flags` those with none. Any other
    /// `--option` is refused. A text may look like an option: an argument
    /// with a space in it is a word, and so is every argument after `--`.
    init(_ raw: [String], valued: Set<String>, flags known: Set<String> = []) throws(UsageError) {
        var rest = raw[...]
        var optionsEnded = false
        while let argument = rest.popFirst() {
            if !optionsEnded, argument == Self.optionsEnd {
                optionsEnded = true
                continue
            }
            guard !optionsEnded, Self.isOption(argument) else {
                words.append(argument)
                continue
            }
            if known.contains(argument) {
                flags.insert(argument)
                continue
            }
            guard valued.contains(argument) else { throw UsageError("unknown option `\(argument)`") }
            guard let value = rest.popFirst() else { throw UsageError("`\(argument)` needs a value") }
            options[argument] = value
            repeated[argument, default: []].append(value)
        }
    }

    /// The argument that ends the options: every argument after it is a word.
    static let optionsEnd = "--"

    /// Whether `argument` is written as an option: `--name`. No option's
    /// name has a space in it, so a sentence that starts with `--` is a word.
    static func isOption(_ argument: String) -> Bool {
        argument.hasPrefix("--") && !argument.contains(where: \.isWhitespace)
    }

    /// The only word, which the command needs: `name` says what it is.
    func one(_ name: String) throws(UsageError) -> String {
        try exactly([name])[0]
    }

    /// The words the command needs, one per name in `names`, in order.
    func exactly(_ names: [String]) throws(UsageError) -> [String] {
        guard words.count >= names.count else { throw UsageError("missing \(names[words.count])") }
        guard words.count == names.count else { throw UsageError("unexpected `\(words[names.count])`") }
        return words
    }

    /// Refuses any word: the command takes none.
    func none() throws(UsageError) {
        if let word = words.first { throw UsageError("unexpected `\(word)`") }
    }
}

/// One command of `havooch`: its name, what it takes, and how its
/// arguments become an `Invocation`.
struct Command: Sendable {
    /// The words that name it: `player seek`.
    var name: String
    /// The name with its arguments, for the usage text.
    var synopsis: String
    var summary: String
    /// The `--options` it takes, each with a value.
    var valuedOptions: Set<String> = []
    /// The `--flags` it takes, each with no value.
    var flags: Set<String> = []
    var parse: @Sendable (Arguments, CommandEnvironment) throws(UsageError) -> Invocation
    /// Whether it acts on one window and takes `--window <id>`, the key
    /// window without it.
    var takesWindow = false

    /// The option that names the window a command acts on.
    static let windowOption = "--window"

    /// The same command, acting on the window `--window` names.
    func onAWindow() -> Command {
        var command = self
        command.takesWindow = true
        return command
    }
}

/// The commands of `havooch`, by name. A new command is a `Command` in
/// one of the lists below. `--json` is accepted on every command.
public enum CommandTable {
    static let commands: [Command] = [OpenCommand.command] + AppCommands.commands + ControlCommands.commands
        + PlayerCommands.commands.map { $0.onAWindow() } + CommentCommands.commands.map { $0.onAWindow() }
        + [ScreenshotCommand.command] + WindowCommands.commands + ListenerCommands.commands + ThemeCommands.commands
        + SetupCommands.commands + ConfigCommands.commands

    /// The command `arguments` start with, and the arguments after its name.
    static func find(_ arguments: [String]) -> (Command, [String])? {
        // The longest name first: `app status` before a one-word command.
        for length in [2, 1] where arguments.count >= length {
            let name = arguments.prefix(length).joined(separator: " ")
            if let command = commands.first(where: { $0.name == name }) {
                return (command, Array(arguments.dropFirst(length)))
            }
        }
        return nil
    }

    public static var usageText: String {
        let width = commands.map(\.synopsis.count).max() ?? 0
        let lines = commands.map { command in
            "  havooch " + command.synopsis.padding(toLength: width, withPad: " ", startingAt: 0) + "  " + command.summary
        }
        return """
            usage: havooch <command> [--json]

            \(lines.joined(separator: "\n"))

            --window <id> names the window a command acts on, as `window list` shows it;
            without it, the key window. It goes with app home, app demo, state, screenshot,
            the player, comment, context, send, thread and window close commands.
            --json prints machine output on every command.
            --version prints the version of Havooch this command comes with.
            Exit codes: 0 done, 1 refused or failed, 2 timed out, 64 wrong usage.

            """
    }
}
