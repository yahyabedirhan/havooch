import Foundation
import ReviewWire

/// `havooch version show | find | menu | section`: a project's versions in
/// its window. `show` and `find` are the version switcher's: a segment or
/// a row in its picker, and the picker with a query typed in. `menu` and
/// `section` are All versions over the thread list, and the older
/// version's section a pick in it adds. Each is the operator's, as the
/// person's clicks are.
enum VersionCommands {
    static let commands: [Command] = [
        Command(
            name: "version show", synopsis: "version show <n>",
            summary: "show the project's version n (`3` or `v3`), as its segment or its row in the picker does; the playhead keeps its time"
        ) { arguments, _ throws(UsageError) in
            let written = try arguments.one("<n>")
            guard let number = versionNumber(written) else {
                throw UsageError("`\(written)` isn't a version; write its number, `3` or `v3`")
            }
            return .send(.versionShow(number: number))
        },
        Command(
            name: "version find", synopsis: "version find [<query>] [--close]",
            summary: "open the version picker under the switcher's field, with the query typed in its search field; --close closes it, as Escape does",
            flags: ["--close"]
        ) { arguments, _ throws(UsageError) in
            guard arguments.words.count <= 1 else { throw UsageError("unexpected `\(arguments.words[1])`") }
            guard arguments.flags.contains("--close") else { return .send(.versionPick(query: arguments.words.first ?? "")) }
            if let query = arguments.words.first { throw UsageError("`--close` takes no query, not `\(query)`") }
            return .send(.versionClose)
        },
        Command(
            name: "version menu", synopsis: "version menu [--search <text>] [--close]",
            summary: "open All versions over a project's thread list, as a click on it does; --search types in its search field (a number, v12, or words of a label); --close closes it",
            valuedOptions: ["--search"], flags: ["--close"]
        ) { arguments, _ throws(UsageError) in
            try arguments.none()
            guard arguments.flags.contains("--close") else { return .send(.threadVersionsOpen(search: arguments.options["--search"])) }
            if arguments.options["--search"] != nil { throw UsageError("`--close` takes no `--search`") }
            return .send(.threadVersionsClose)
        },
        Command(
            name: "version section", synopsis: "version section <n> [--remove]",
            summary: "pick version <n> in All versions, as a click on it does: an older version's section joins the thread list under the last three, and the list scrolls to it; --remove takes a picked version's section out, as its close button does",
            flags: ["--remove"]
        ) { arguments, _ throws(UsageError) in
            let word = try arguments.one("<n>")
            let digits = word.hasPrefix("v") ? String(word.dropFirst()) : word
            guard let number = Int(digits), number >= 1 else { throw UsageError("`\(word)` isn't a version; write its number, 1 or more (`12` or `v12`)") }
            return .send(.threadVersion(number: number, remove: arguments.flags.contains("--remove")))
        },
    ]

    /// The number of `3` or `v3`; nil for anything else, and below 1.
    static func versionNumber(_ text: String) -> Int? {
        let bare = text.lowercased().hasPrefix("v") ? String(text.dropFirst()) : text
        guard !bare.isEmpty, bare.allSatisfy(\.isASCII), let number = Int(bare), number >= 1 else { return nil }
        return number
    }
}
