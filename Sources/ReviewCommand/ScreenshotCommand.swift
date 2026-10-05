import Foundation
import ReviewWire

/// `havooch screenshot <abs.png> [--appearance light|dark]
/// [--hide-agent-indicator] [--window main|settings|about]`: the app's window as
/// a PNG. The path is absolute, as the contract says. The agent-control
/// indicator shows as the person sees it; `--hide-agent-indicator` leaves
/// it out. `--window settings` captures the Settings window instead, and
/// `--window about` the About panel.
enum ScreenshotCommand {
    static let command = Command(
        name: "screenshot", synopsis: "screenshot <abs.png> [--appearance light|dark] [--hide-agent-indicator] [--window main|settings|about]",
        summary: "save the app's window, its Settings window or its About panel as a PNG, with the agent-control indicator unless hidden",
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
        var window = ControlRequest.Window.main
        if let name = arguments.options["--window"] {
            guard let known = ControlRequest.Window(rawValue: name) else {
                throw UsageError("no window `\(name)`; it's main, settings or about")
            }
            window = known
        }
        return .send(.screenshot(
            path: URL(fileURLWithPath: path).standardizedFileURL.path, appearance: appearance,
            hideAgentIndicator: arguments.flags.contains("--hide-agent-indicator"), window: window
        ))
    }
}
