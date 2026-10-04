import Foundation
import ReviewWire

/// `video-review screenshot <abs.png> [--appearance light|dark]
/// [--with-banner]`: the app's window as a PNG. The path is absolute, as the
/// contract says. The lease banner is left out, since the agent that takes
/// the screenshot always holds the lease; `--with-banner` keeps it in.
enum ScreenshotCommand {
    static let command = Command(
        name: "screenshot", synopsis: "screenshot <abs.png> [--appearance light|dark] [--with-banner]",
        summary: "save the app's window as a PNG, without the lease banner unless asked",
        valuedOptions: ["--appearance"], flags: ["--with-banner"]
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
            withBanner: arguments.flags.contains("--with-banner")
        ))
    }
}
