import Foundation
import ReviewWire

enum WindowCommands {
    static let group = CommandGroup(
        name: "window", summary: "list, open, close and resize windows", section: .drive, commands: [
            Command(
                name: "window list", summary: "list every window, what it holds, and which one is key",
                description: "Each window's id (`w1`, `w2`) is what --window takes.", examples: ["", "--json"], role: .free
            ) { arguments, _ throws(UsageError) in
                try arguments.none()
                return .send(.windowList)
            },
            Command(
                name: "window new", summary: "open a new empty window on the home screen",
                description: "As File › New Window does.", examples: [""], role: .operator
            ) { arguments, _ throws(UsageError) in
                try arguments.none()
                return .send(.windowNew)
            },
            Command(
                name: "window close", arguments: "[<id>]", summary: "close a window, or the key window",
                description: "As its close button does.", examples: ["", "w2"], role: .operator
            ) { arguments, _ throws(UsageError) in
                guard arguments.words.count <= 1 else { throw UsageError("unexpected `\(arguments.words[1])`") }
                if let id = arguments.words.first, arguments.options[Command.windowOption].map({ $0 != id }) == true {
                    throw UsageError("name the window once: `window close \(id)` or `--window \(id)`")
                }
                return .send(.windowClose, window: arguments.words.first)
            }.onAWindow(),
            Command(
                name: "window resize", arguments: "<width>", summary: "set a window's content width in points",
                description: "The window keeps its minimum width.", examples: ["780", "1200 --window w2"], role: .operator
            ) { arguments, _ throws(UsageError) in
                guard arguments.words.count == 1, let width = Int(arguments.words[0]), width > 0 else {
                    throw UsageError("window resize needs a positive width in points")
                }
                return .send(.windowResize(width: width))
            }.onAWindow(),
        ]
    )
}
