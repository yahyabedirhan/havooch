import Foundation
import ReviewWire

/// `havooch window list | new | close | resize`: the app's windows. Each window
/// holds one video, or none and shows the home screen. `list` names them
/// (`w1`, `w2`…) for `--window`; `new` makes an empty one, as File › New
/// Window does; `close` closes one, as its close button does.
enum WindowCommands {
    static let commands: [Command] = [
        Command(name: "window list", synopsis: "window list", summary: "every window, what it holds, and which one is key") {
            arguments, _ throws(UsageError) in
            try arguments.none()
            return .send(.windowList)
        },
        Command(name: "window new", synopsis: "window new", summary: "a new empty window that shows the home screen, as File › New Window") {
            arguments, _ throws(UsageError) in
            try arguments.none()
            return .send(.windowNew)
        },
        Command(name: "window close", synopsis: "window close [<id>]", summary: "close a window, or the key window, as its close button does") {
            arguments, _ throws(UsageError) in
            guard arguments.words.count <= 1 else { throw UsageError("unexpected `\(arguments.words[1])`") }
            if let id = arguments.words.first, arguments.options[Command.windowOption].map({ $0 != id }) == true {
                throw UsageError("name the window once: `window close \(id)` or `--window \(id)`")
            }
            return .send(.windowClose, window: arguments.words.first)
        }.onAWindow(),
        Command(name: "window resize", synopsis: "window resize <width>", summary: "set the key window's content width in points, subject to its minimum") {
            arguments, _ throws(UsageError) in
            guard arguments.words.count == 1, let width = Int(arguments.words[0]), width > 0 else {
                throw UsageError("window resize needs a positive width in points")
            }
            return .send(.windowResize(width: width))
        }.onAWindow(),
    ]
}
