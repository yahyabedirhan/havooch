import Foundation
import ReviewConfig
import ReviewWire

enum ConfigCommands {
    static let group = CommandGroup(
        name: "config", summary: "find and check config.toml", section: .drive, commands: [
            Command(
                name: "config path", summary: "print where config.toml and your themes are",
                description: "It needs no app.", examples: ["", "--json"], role: .free
            ) { arguments, _ throws(UsageError) in
                try arguments.none()
                return .configPath
            },
            Command(
                name: "config check", summary: "check that config.toml reads",
                description: "It prints each problem with its line, and needs no app.", examples: ["", "--json"], role: .free,
                exitCodes: "1 when config.toml doesn't read."
            ) { arguments, _ throws(UsageError) in
                try arguments.none()
                return .configCheck
            },
            Command(
                name: "config close-notice", summary: "close the settings notice in the window",
                description: "As its close button does.", examples: [""], role: .operator
            ) { arguments, _ throws(UsageError) in
                try arguments.none()
                return .send(.configDismiss)
            },
        ]
    )

    static func location(_ environment: CommandEnvironment) -> ConfigLocation {
        ConfigLocation(variables: environment.variables, movedSupport: SupportFolder.moved(environment: environment.variables))
    }

    static func path(json: Bool, environment: CommandEnvironment) -> CommandResult {
        let location = location(environment)
        guard json else { return CommandResult(output: location.file.path + "\n") }
        let exists = FileManager.default.fileExists(atPath: location.file.path)
        return encoded(Path(config: location.file.path, themes: location.themesFolder.path, exists: exists))
    }

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

    static func encoded(_ value: some Encodable) -> CommandResult {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(value), let text = String(data: data, encoding: .utf8) else {
            return .refused("couldn't write the answer as JSON")
        }
        return CommandResult(output: text + "\n")
    }
}
