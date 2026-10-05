import Foundation
import ReviewWire

/// `havooch theme list | set <name>`. `list` is free: it changes
/// nothing a person sees. `set` is the operator's: it pins a theme, or
/// unpins with `system`. The app knows the themes, so both ask it.
enum ThemeCommands {
    static let commands: [Command] = [
        Command(name: "theme list", synopsis: "theme list", summary: "every theme, built-in or yours, and which one is active") {
            arguments, _ throws(UsageError) in
            try arguments.none()
            return .send(.themeList)
        },
        Command(
            name: "theme set", synopsis: "theme set <name|system>",
            summary: "pin a theme by its name; `system` follows the Mac's light or dark appearance again"
        ) { arguments, _ throws(UsageError) in
            let name = try arguments.one("<name>")
            guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { throw UsageError("`theme set` needs a theme's name") }
            return .send(.themeSet(name: name))
        },
    ]
}
