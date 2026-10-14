import Foundation
import ReviewWire

enum LookCommands {
    static let group = CommandGroup(
        name: nil, summary: "look at the app and learn the command", section: .look, commands: [state, screenshot, help]
    )

    private static let state = Command(
        name: "state", summary: "print everything the app shows",
        description: "It prints the window's video and player, and every window. With --json, the whole state as one object.",
        examples: ["", "--json", "--window w2"], role: .free
    ) { arguments, _ throws(UsageError) in
        try arguments.none()
        return .send(.state)
    }.onAWindow()

    private static let help = Command(
        name: "help", arguments: "[<group> [<verb>]]",
        summary: "print the help of the command, a group or one command",
        description: "With --json, every group and command, with its usage, role and options, for an agent.",
        examples: ["", "player", "player seek", "--json"], role: .free, listing: .unlisted
    ) { arguments, _ throws(UsageError) in
        guard arguments.words.count <= 2 else { throw UsageError("unexpected `\(arguments.words[2])`") }
        return .help(arguments.words)
    }

    private static let screenshot = Command(
        name: "screenshot", arguments: "<abs.png> [--appearance light|dark] [--hide-agent-indicator] [--window main|settings|about|first-run|<id>]",
        summary: "save a window as a PNG",
        description: "It saves the key window, the player window --window names, Settings, the About panel or the first-run "
            + "window. The agent-control indicator shows as the person sees it, unless --hide-agent-indicator leaves it out.",
        examples: ["/tmp/shot.png", "/tmp/dark.png --appearance dark --window w2", "/tmp/settings.png --window settings"],
        role: .operator,
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
