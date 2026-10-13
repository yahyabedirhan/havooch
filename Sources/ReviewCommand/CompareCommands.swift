import Foundation
import ReviewWire

/// `havooch compare open | find | set | swap | start | exit`: the compare
/// control's own actions in a project's window. Each is the operator's, as
/// the person's clicks on the Compare button, a side, the swap button and
/// Exit Compare are.
enum CompareCommands {
    static let group = CommandGroup(
        name: "compare", summary: "compare two versions", section: .drive, commands: [
            Command(
                name: "compare open", summary: "open the compare popover",
                description: "As a click on the Compare button does: the popover opens on the previous version and the one on screen.",
                examples: [""], role: .operator
            ) { arguments, _ throws(UsageError) in
                try arguments.none()
                return .send(.compareOpen)
            },
            Command(
                name: "compare find", arguments: "left|right [<query>]", summary: "open one side's version picker with a query typed in",
                description: "In the compare popover, as a click on that side does.",
                examples: ["left", "right \"alt opening\""], role: .operator
            ) { arguments, _ throws(UsageError) in
                guard let written = arguments.words.first else { throw UsageError("missing left|right") }
                guard arguments.words.count <= 2 else { throw UsageError("unexpected `\(arguments.words[2])`") }
                return .send(.comparePick(side: try side(written), query: arguments.words.count == 2 ? arguments.words[1] : ""))
            },
            Command(
                name: "compare set",
                arguments: "[--left <n>] [--right <n>] [--layout side-by-side|flip|slider] [--side left|right] [--slider <0-1>]",
                summary: "change the comparison",
                description: "--left and --right set a side's version, and the other side's version swaps them. --layout sets "
                    + "the layout, --side the side messages go to (in Flip, the side showing), and --slider the slider.",
                examples: ["--left 2 --right 3", "--layout slider --slider 0.5", "--layout flip --side right"],
                role: .operator, valuedOptions: ["--left", "--right", "--layout", "--side", "--slider"]
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
                name: "compare swap", summary: "exchange the left and the right version",
                description: "As the swap button does.", examples: [""], role: .operator
            ) { arguments, _ throws(UsageError) in
                try arguments.none()
                return .send(.compareSwap)
            },
            Command(
                name: "compare start", summary: "compare the two versions on one playhead",
                description: "As the popover's Show side by side or Compare does.", examples: [""], role: .operator
            ) { arguments, _ throws(UsageError) in
                try arguments.none()
                return .send(.compareStart)
            },
            Command(
                name: "compare exit", summary: "go back to one version, the right side's",
                description: "As Exit Compare and Escape do; in the popover, as Cancel does.", examples: [""], role: .operator
            ) { arguments, _ throws(UsageError) in
                try arguments.none()
                return .send(.compareExit)
            },
        ].map { $0.onAWindow() }
    )

    /// `versionNumber`, refused in words.
    private static func version(_ text: String) throws(UsageError) -> Int {
        guard let number = VersionCommands.versionNumber(text) else { throw UsageError("`\(text)` isn't a version; write its number, `3` or `v3`") }
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
