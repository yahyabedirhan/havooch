import Foundation
import ReviewWire

/// `havooch state | screenshot`: looking at the app. `state` prints
/// everything the window shows. `screenshot <abs.png> [--appearance
/// light|dark] [--hide-agent-indicator] [--window
/// main|settings|about|first-run|<id>]` saves a window as a PNG: the key
/// window, or the window `--window <id>` names. The path is absolute, as
/// the contract says. The agent-control indicator shows as the person sees
/// it; `--hide-agent-indicator` leaves it out. `--window settings` captures
/// the Settings window instead, and `--window about` the About panel,
/// `--window first-run` the first-run window.
enum LookCommands {
    static let commands: [Command] = [
        Command(name: "state", synopsis: "state", summary: "everything the app shows: the window's video and player, and every window") {
            arguments, _ throws(UsageError) in
            try arguments.none()
            return .send(.state)
        }.onAWindow(),
        screenshot,
    ]

    /// `screenshot` names its own window: a player window by its id, or
    /// one of the app's other windows by its name.
    private static let screenshot = Command(
        name: "screenshot", synopsis: "screenshot <abs.png> [--appearance light|dark] [--hide-agent-indicator] [--window main|settings|about|first-run|<id>]",
        summary: "save a window (the key one, or --window <id>), Settings, the About panel or the first-run window as a PNG, with the agent-control indicator unless hidden",
        valuedOptions: ["--appearance", "--window"], flags: ["--hide-agent-indicator"]
    ) { arguments, _ throws(UsageError) in
        let path = try arguments.one("<abs.png>")
        guard path.hasPrefix("/") else { throw UsageError("`\(path)` isn't an absolute path") }
        guard path.lowercased().hasSuffix(".png") else { throw UsageError("`\(path)` isn't a .png file") }
        var appearance: ControlRequest.Appearance?
        if let name = arguments.options["--appearance"] {
            guard let known = ControlRequest.Appearance(rawValue: name) else {
                throw UsageError("no appearance `\(name)`; it's light or dark")
            }
            appearance = known
        }
        // `main`, `settings`, `about` or `first-run`, or a player window by its id (`w2`).
        let name = arguments.options["--window"]
        let window = name.flatMap(ControlRequest.Window.init(rawValue:)) ?? .main
        if let name, name.isEmpty { throw UsageError("`--window` needs main, settings, about, first-run or a window id") }
        return .send(
            .screenshot(
                path: URL(fileURLWithPath: path).standardizedFileURL.path, appearance: appearance,
                hideAgentIndicator: arguments.flags.contains("--hide-agent-indicator"), window: window
            ),
            window: window == .main && name != ControlRequest.Window.main.rawValue ? name : nil
        )
    }
}
