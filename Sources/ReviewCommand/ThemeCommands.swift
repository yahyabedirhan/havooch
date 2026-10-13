import Foundation
import ReviewWire

/// `havooch theme list | set <name>`. `list` is free: it changes
/// nothing a person sees. `set` is the operator's: it pins a theme, or
/// unpins with `system`. The app knows the themes, so both ask it.
enum ThemeCommands {
    static let group = CommandGroup(
        name: "theme", summary: "list and set themes", section: .drive, commands: [
            Command(
                name: "theme list", summary: "list every theme, built-in or yours, and which one is active",
                examples: ["", "--json"], role: .free
            ) { arguments, _ throws(UsageError) in
                try arguments.none()
                return .send(.themeList)
            },
            Command(
                name: "theme set", arguments: "<name|system>", summary: "pin a theme by its name",
                description: "`system` unpins it: the app follows the Mac's light or dark appearance again.",
                examples: ["graphite", "system"], role: .operator
            ) { arguments, _ throws(UsageError) in
                let name = try arguments.one("<name>")
                guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { throw UsageError("`theme set` needs a theme's name") }
                return .send(.themeSet(name: name))
            },
        ]
    )
}
