import Foundation
import ReviewWire

enum SetupCommands {
    static let group = CommandGroup(
        name: "setup", summary: "link the command and install the skill", section: .drive, commands: [
            Command(
                name: "setup status", summary: "print what Havooch detects",
                description: "The command link, each harness and its skill, and the skill install with its log.",
                examples: ["", "--json"], role: .free
            ) { arguments, _ throws(UsageError) in
                try arguments.none()
                return .send(.setupStatus)
            },
            Command(
                name: "setup link", arguments: "[--dry-run]", summary: "link the havooch command in ~/.local/bin",
                description: "As Link does. A failure prints the ln -sf line to run. --dry-run only says what it would do.",
                examples: ["", "--dry-run"], role: .operator, flags: ["--dry-run"]
            ) { arguments, _ throws(UsageError) in
                try arguments.none()
                return .send(.setupLink(dryRun: arguments.flags.contains("--dry-run")))
            },
            Command(
                name: "setup install", arguments: "[--harness <name>]... [--dry-run]",
                summary: "install the havooch-mate skill globally",
                description: "As Run Command does: npx skills add, for each --harness, or for every harness found without it. "
                    + "setup status follows its log. --dry-run only prints the command.",
                examples: ["", "--harness claude-code --harness codex", "--dry-run"],
                role: .operator, valuedOptions: ["--harness"], flags: ["--dry-run"]
            ) { arguments, _ throws(UsageError) in
                try arguments.none()
                let harnesses = arguments.repeated["--harness"] ?? []
                if harnesses.contains(where: { $0.trimmingCharacters(in: .whitespaces).isEmpty }) {
                    throw UsageError("`--harness` needs a harness's name")
                }
                return .send(.setupInstall(harnesses: harnesses, dryRun: arguments.flags.contains("--dry-run")))
            },
            Command(
                name: "setup cancel", summary: "stop the running skill install",
                description: "As Cancel does.", examples: [""], role: .operator
            ) { arguments, _ throws(UsageError) in
                try arguments.none()
                return .send(.setupCancel)
            },
        ]
    )
}
