import Foundation
import ReviewWire

/// `havooch version show | pick | close`: the version switcher's own
/// actions in a project's window (E10), each the operator's, as the
/// person's clicks on a segment, on the field and on a row of the picker
/// are. Compare's commands join them here.
enum CompareCommands {
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
            name: "version pick", synopsis: "version pick [<query>]",
            summary: "open the version picker under the switcher's field, with the query typed in its search field"
        ) { arguments, _ throws(UsageError) in
            guard arguments.words.count <= 1 else { throw UsageError("unexpected `\(arguments.words[1])`") }
            return .send(.versionPick(query: arguments.words.first ?? ""))
        },
        Command(
            name: "version close", synopsis: "version close",
            summary: "close the version picker, as Escape does"
        ) { arguments, _ throws(UsageError) in
            try arguments.none()
            return .send(.versionClose)
        },
    ]

    /// The number of `3` or `v3`; nil for anything else, and below 1.
    static func versionNumber(_ text: String) -> Int? {
        let bare = text.lowercased().hasPrefix("v") ? String(text.dropFirst()) : text
        guard !bare.isEmpty, bare.allSatisfy(\.isASCII), let number = Int(bare), number >= 1 else { return nil }
        return number
    }
}
