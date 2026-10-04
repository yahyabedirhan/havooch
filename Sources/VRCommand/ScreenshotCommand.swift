import Foundation
import VRWire

/// `video-review screenshot <abs.png> [--appearance light|dark]`: the app's
/// own window as a PNG.
public enum ScreenshotCommand {
    public static let entry = CommandTable.Entry(
        name: "screenshot",
        summary: "<abs.png> [--appearance light|dark]: save the app's window as a PNG",
        run: run
    )

    static let usageText = """
        usage: video-review screenshot <abs.png> [--appearance light|dark]

          Saves the app's window as it looks, and prints the file's path. The
          path must be absolute and end in .png; its folder must exist.

          --appearance   light or dark: the window drawn in that appearance,
                         then back to the Mac's

        When the app can't capture its window, it renders the window's
        contents itself, writes that and says so on standard error, still
        exit 0. Exits 1 when the app isn't running or nothing could be
        written.

        """

    static func parse(_ arguments: [String]) -> Result<ControlRequest, CommandResult> {
        if Arguments.asksForHelp(arguments) {
            return .failure(CommandResult(output: usageText))
        }
        var path: String?
        var appearance: ControlRequest.Appearance?
        var rest = arguments[...]
        while let argument = rest.popFirst() {
            switch argument {
            case "--appearance":
                guard let name = rest.popFirst() else {
                    return .failure(misread("video-review screenshot: --appearance needs light or dark"))
                }
                guard let known = ControlRequest.Appearance(rawValue: name) else {
                    return .failure(misread("video-review screenshot: no appearance `\(name)`; it's light or dark"))
                }
                appearance = known
            case let option where option.hasPrefix("-") && option.count > 1:
                return .failure(misread("video-review screenshot: unknown option `\(option)`"))
            case let file where path == nil:
                path = file
            case let extra:
                return .failure(misread("video-review screenshot: unexpected `\(extra)`"))
            }
        }
        guard let path else {
            return .failure(misread("video-review screenshot: missing <abs.png>"))
        }
        guard path.hasPrefix("/") else {
            return .failure(misread("video-review screenshot: `\(path)` isn't an absolute path"))
        }
        guard path.lowercased().hasSuffix(".png") else {
            return .failure(misread("video-review screenshot: `\(path)` isn't a .png file"))
        }
        return .success(.screenshot(path: URL(fileURLWithPath: path).standardizedFileURL.path, appearance: appearance))
    }

    private static func misread(_ line: String) -> CommandResult {
        .misread(line, usage: usageText)
    }

    static func run(_ arguments: [String], context: CommandContext) -> CommandResult {
        context.send(parse(arguments))
    }
}
