import Foundation
import ReviewWire

/// What a command line asks for.
enum Invocation: Equatable, Sendable {
    /// A request the running app answers.
    case send(ControlRequest)
    /// `app status`: answered without the app when it isn't running.
    case appStatus
    /// `app open`: launch the app unless it runs on the data asked for, on
    /// the demo's support folder when there is one.
    case appOpen(demo: URL?)
    /// `app quit`: ask the app to quit, then wait until it's gone.
    case appQuit
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
    var options: [String: String] = [:]

    /// Reads `raw`; `valued` names the options the command takes, each
    /// with a value after it. Any other `--option` is refused.
    init(_ raw: [String], valued: Set<String>) throws(UsageError) {
        var rest = raw[...]
        while let argument = rest.popFirst() {
            guard argument.hasPrefix("--") else {
                words.append(argument)
                continue
            }
            guard valued.contains(argument) else { throw UsageError("unknown option `\(argument)`") }
            guard let value = rest.popFirst() else { throw UsageError("`\(argument)` needs a value") }
            options[argument] = value
        }
    }

    /// The only word, which the command needs: `name` says what it is.
    func one(_ name: String) throws(UsageError) -> String {
        guard let word = words.first else { throw UsageError("missing \(name)") }
        guard words.count == 1 else { throw UsageError("unexpected `\(words[1])`") }
        return word
    }

    /// Refuses any word: the command takes none.
    func none() throws(UsageError) {
        if let word = words.first { throw UsageError("unexpected `\(word)`") }
    }
}

/// One command of `video-review`: its name, what it takes, and how its
/// arguments become an `Invocation`.
struct Command: Sendable {
    /// The words that name it: `player seek`.
    var name: String
    /// The name with its arguments, for the usage text.
    var synopsis: String
    var summary: String
    /// The `--options` it takes, each with a value.
    var valuedOptions: Set<String> = []
    var parse: @Sendable (Arguments, CommandEnvironment) throws(UsageError) -> Invocation
}

/// The commands of `video-review`, by name. A new command is a `Command` in
/// one of the lists below. `--json` is accepted on every command.
public enum CommandTable {
    static let commands: [Command] = AppCommands.commands + PlayerCommands.commands + [ScreenshotCommand.command]

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
            "  video-review " + command.synopsis.padding(toLength: width, withPad: " ", startingAt: 0) + "  " + command.summary
        }
        return """
            usage: video-review <command> [--json]

            \(lines.joined(separator: "\n"))

            --json prints machine output on every command.
            Exit codes: 0 done, 1 refused or failed, 2 timed out, 64 wrong usage.

            """
    }
}
