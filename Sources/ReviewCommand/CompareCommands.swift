import Foundation
import ReviewWire

/// `havooch version show | pick | close`: the version switcher's own
/// actions in a project's window, and `havooch compare open | pick |
/// set | swap | start | exit`: the compare control's. Each is the
/// operator's, as the person's clicks on a segment, a row, the Compare
/// button, a side, the swap button and Exit Compare are.
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
        Command(
            name: "compare open", synopsis: "compare open",
            summary: "open the compare popover under the Compare button, on the previous version and the one on screen"
        ) { arguments, _ throws(UsageError) in
            try arguments.none()
            return .send(.compareOpen)
        },
        Command(
            name: "compare pick", synopsis: "compare pick <left|right> [<query>]",
            summary: "open one side's version picker in the compare popover, with the query typed in its search field"
        ) { arguments, _ throws(UsageError) in
            guard let written = arguments.words.first else { throw UsageError("missing <left|right>") }
            guard arguments.words.count <= 2 else { throw UsageError("unexpected `\(arguments.words[2])`") }
            return .send(.comparePick(side: try side(written), query: arguments.words.count == 2 ? arguments.words[1] : ""))
        },
        Command(
            name: "compare set",
            synopsis: "compare set [--left <n>] [--right <n>] [--layout side-by-side|flip|slider] [--side left|right] [--slider <0-1>]",
            summary: "change the comparison: a side's version (the other side's swaps them), the layout, the side messages go to "
                + "(in Flip, the side showing) and the slider",
            valuedOptions: ["--left", "--right", "--layout", "--side", "--slider"]
        ) { arguments, _ throws(UsageError) in
            try arguments.none()
            var change = CompareChange()
            change.left = try arguments.options["--left"].map { written throws(UsageError) in try version(written) }
            change.right = try arguments.options["--right"].map { written throws(UsageError) in try version(written) }
            if let written = arguments.options["--layout"] {
                guard let layout = CompareLayout(rawValue: written.lowercased()) else {
                    throw UsageError("`\(written)` isn't a layout; write `side-by-side`, `flip` or `slider`")
                }
                change.layout = layout
            }
            change.side = try arguments.options["--side"].map { written throws(UsageError) in try side(written) }
            if let written = arguments.options["--slider"] {
                guard let fraction = Double(written), (0...1).contains(fraction) else {
                    throw UsageError("`\(written)` isn't a slider position; write a number from 0 to 1, such as 0.5")
                }
                change.slider = fraction
            }
            guard !change.isEmpty else {
                throw UsageError("compare set needs --left, --right, --layout, --side or --slider")
            }
            return .send(.compareSet(change))
        },
        Command(
            name: "compare swap", synopsis: "compare swap",
            summary: "exchange the left and the right version, as the swap button does"
        ) { arguments, _ throws(UsageError) in
            try arguments.none()
            return .send(.compareSwap)
        },
        Command(
            name: "compare start", synopsis: "compare start",
            summary: "compare the two versions on one playhead, as the popover's Show side by side or Compare does"
        ) { arguments, _ throws(UsageError) in
            try arguments.none()
            return .send(.compareStart)
        },
        Command(
            name: "compare exit", synopsis: "compare exit",
            summary: "back to one version, the right side's, as Exit Compare and Escape do; in the popover, Cancel"
        ) { arguments, _ throws(UsageError) in
            try arguments.none()
            return .send(.compareExit)
        },
    ]

    /// The number of `3` or `v3`; nil for anything else, and below 1.
    static func versionNumber(_ text: String) -> Int? {
        let bare = text.lowercased().hasPrefix("v") ? String(text.dropFirst()) : text
        guard !bare.isEmpty, bare.allSatisfy(\.isASCII), let number = Int(bare), number >= 1 else { return nil }
        return number
    }

    /// `versionNumber`, refused in words.
    private static func version(_ text: String) throws(UsageError) -> Int {
        guard let number = versionNumber(text) else { throw UsageError("`\(text)` isn't a version; write its number, `3` or `v3`") }
        return number
    }

    /// The side `text` names, in any case.
    private static func side(_ text: String) throws(UsageError) -> CompareSide {
        guard let side = CompareSide(rawValue: text.lowercased()) else {
            throw UsageError("`\(text)` isn't a side; write `left` or `right`")
        }
        return side
    }
}
