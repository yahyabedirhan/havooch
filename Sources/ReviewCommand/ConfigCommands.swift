import Foundation
import ReviewConfig
import ReviewWire

/// `havooch config path | check | dismiss` (ADR 0002). `path` and `check`
/// read the file themselves: they need no app, and no lease. `dismiss` is
/// the operator's: the settings notice in the window goes. The file is where
/// `ConfigLocation` says, so a command with `HAVOOCH_SUPPORT_DIR` set
/// reads that folder's `config/config.toml`, never the person's.
enum ConfigCommands {
    static let commands: [Command] = [
        Command(
            name: "config path", synopsis: "config path",
            summary: "where config.toml and your themes are; needs no app"
        ) { arguments, _ throws(UsageError) in
            try arguments.none()
            return .configPath
        },
        Command(
            name: "config check", synopsis: "config check",
            summary: "whether config.toml reads, each problem with its line; exit 1 when it doesn't; needs no app"
        ) { arguments, _ throws(UsageError) in
            try arguments.none()
            return .configCheck
        },
        Command(
            name: "config dismiss", synopsis: "config dismiss",
            summary: "close the settings notice in the window, as its close button does"
        ) { arguments, _ throws(UsageError) in
            try arguments.none()
            return .send(.configDismiss)
        },
    ]

    /// The file the environment's settings are in.
    static func location(_ environment: CommandEnvironment) -> ConfigLocation {
        ConfigLocation(variables: environment.variables, movedSupport: SupportFolder.moved(environment: environment.variables))
    }

    /// `config path`: the file's path; with `--json`, the themes folder and
    /// whether the file exists too.
    static func path(json: Bool, environment: CommandEnvironment) -> CommandResult {
        let location = location(environment)
        guard json else { return CommandResult(output: location.file.path + "\n") }
        let exists = FileManager.default.fileExists(atPath: location.file.path)
        return encoded(Path(config: location.file.path, themes: location.themesFolder.path, exists: exists))
    }

    /// `config check`: the verdict, as `config-status.json` holds it with
    /// `--json`. Exit 1 when the file doesn't read.
    static func check(json: Bool, environment: CommandEnvironment) -> CommandResult {
        let verdict = location(environment).check(at: environment.now()).verdict
        var result = json ? encoded(verdict) : CommandResult(output: verdict.lines)
        if !verdict.accepted { result.exitCode = CommandResult.refusedCode }
        return result
    }

    private struct Path: Encodable {
        var config: String
        var themes: String
        var exists: Bool
    }

    /// `value` as the app's JSON is printed: readable, keys sorted.
    static func encoded(_ value: some Encodable) -> CommandResult {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(value), let text = String(data: data, encoding: .utf8) else {
            return .refused("couldn't write the answer as JSON")
        }
        return CommandResult(output: text + "\n")
    }
}
