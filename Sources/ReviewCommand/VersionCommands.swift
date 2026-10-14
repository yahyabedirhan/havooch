import Foundation
import ReviewWire

enum VersionCommands {
    static let group = CommandGroup(
        name: "version", summary: "show and find a project's versions", section: .drive, commands: [
            Command(
                name: "version show", arguments: "<n>", summary: "show one of the project's versions",
                description: "As its segment, or its row in the picker, does. The playhead keeps its time. <n> is `3` or `v3`.",
                examples: ["3", "v2 --window w2"], role: .operator
            ) { arguments, _ throws(UsageError) in
                let written = try arguments.one("<n>")
                guard let number = versionNumber(written) else {
                    throw UsageError("`\(written)` isn't a version; write its number, `3` or `v3`")
                }
                return .send(.versionShow(number: number))
            },
            Command(
                name: "version find", arguments: "[<query>] [--close]", summary: "open the version picker with a query typed in",
                description: "The picker opens under the switcher's field. --close closes it, as Escape does.",
                examples: ["", "\"alt opening\"", "--close"], role: .operator, flags: ["--close"]
            ) { arguments, _ throws(UsageError) in
                guard arguments.words.count <= 1 else { throw UsageError("unexpected `\(arguments.words[1])`") }
                guard arguments.flags.contains("--close") else { return .send(.versionPick(query: arguments.words.first ?? "")) }
                if let query = arguments.words.first { throw UsageError("`--close` takes no query, not `\(query)`") }
                return .send(.versionClose)
            },
            Command(
                name: "version menu", arguments: "[--search <text>] [--close]",
                summary: "open All versions over a project's thread list",
                description: "As a click on it does. --search types in its search field: a number, v12, or words of a label. "
                    + "--close closes it.",
                examples: ["", "--search v12", "--close"], role: .operator, valuedOptions: ["--search"], flags: ["--close"]
            ) { arguments, _ throws(UsageError) in
                try arguments.none()
                guard arguments.flags.contains("--close") else { return .send(.threadVersionsOpen(search: arguments.options["--search"])) }
                if arguments.options["--search"] != nil { throw UsageError("`--close` takes no `--search`") }
                return .send(.threadVersionsClose)
            },
            Command(
                name: "version section", arguments: "<n> [--remove]",
                summary: "add an older version's section to the thread list",
                description: "As a click on it in All versions does: the section joins the thread list under the last three, "
                    + "and the list scrolls to it. --remove takes it out, as its close button does.",
                examples: ["12", "v12 --remove"], role: .operator, flags: ["--remove"]
            ) { arguments, _ throws(UsageError) in
                let word = try arguments.one("<n>")
                let digits = word.hasPrefix("v") ? String(word.dropFirst()) : word
                guard let number = Int(digits), number >= 1 else { throw UsageError("`\(word)` isn't a version; write its number, 1 or more (`12` or `v12`)") }
                return .send(.threadVersion(number: number, remove: arguments.flags.contains("--remove")))
            },
        ].map { $0.onAWindow() }
    )

    static func versionNumber(_ text: String) -> Int? {
        let bare = text.lowercased().hasPrefix("v") ? String(text.dropFirst()) : text
        guard !bare.isEmpty, bare.allSatisfy(\.isASCII), let number = Int(bare), number >= 1 else { return nil }
        return number
    }
}
