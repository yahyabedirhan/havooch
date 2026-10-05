import Foundation
import ReviewWire

/// `video-review screenshot <abs.png> [--appearance light|dark]
/// [--hide-agent-indicator]`: the app's window as a PNG. The path is
/// absolute, as the contract says. The agent-control indicator shows as the
/// person sees it; `--hide-agent-indicator` leaves it out.
enum ScreenshotCommand {
    static let command = Command(
        name: "screenshot", synopsis: "screenshot <abs.png> [--appearance light|dark] [--hide-agent-indicator]",
        summary: "save the app's window as a PNG, with the agent-control indicator unless hidden",
        valuedOptions: ["--appearance"], flags: ["--hide-agent-indicator"]
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
        return .send(.screenshot(
            path: URL(fileURLWithPath: path).standardizedFileURL.path, appearance: appearance,
            hideAgentIndicator: arguments.flags.contains("--hide-agent-indicator")
        ))
    }
}
