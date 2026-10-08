import Foundation
import ReviewWire

/// `havooch setup status | link | install | cancel`: what the Connect
/// view's setup steps show and do. `status` is free: it changes nothing a
/// person sees. `link`, `install` and `cancel` are the operator's, as Link,
/// Install and Cancel are the person's. The app reads the disk and runs the
/// install, so each asks it.
enum SetupCommands {
    static let commands: [Command] = [
        Command(
            name: "setup status", synopsis: "setup status",
            summary: "what Havooch detects: the command link, each harness and its skill, and the install with its log"
        ) { arguments, _ throws(UsageError) in
            try arguments.none()
            return .send(.setupStatus)
        },
        Command(
            name: "setup link", synopsis: "setup link [--dry-run]",
            summary: "link the havooch command in ~/.local/bin, as Link does; a failure prints the ln -sf line to run; --dry-run only says what it would do",
            flags: ["--dry-run"]
        ) { arguments, _ throws(UsageError) in
            try arguments.none()
            return .send(.setupLink(dryRun: arguments.flags.contains("--dry-run")))
        },
        Command(
            name: "setup install", synopsis: "setup install [--harness <name>]... [--dry-run]",
            summary: "install the havooch-mate skill globally with npx skills add, for each --harness or for every harness found without it, as Install does; setup status follows its log; --dry-run only prints the command",
            valuedOptions: ["--harness"], flags: ["--dry-run"]
        ) { arguments, _ throws(UsageError) in
            try arguments.none()
            let harnesses = arguments.repeated["--harness"] ?? []
            if harnesses.contains(where: { $0.trimmingCharacters(in: .whitespaces).isEmpty }) {
                throw UsageError("`--harness` needs a harness's name")
            }
            return .send(.setupInstall(harnesses: harnesses, dryRun: arguments.flags.contains("--dry-run")))
        },
        Command(name: "setup cancel", synopsis: "setup cancel", summary: "stop the running skill install, as Cancel does") {
            arguments, _ throws(UsageError) in
            try arguments.none()
            return .send(.setupCancel)
        },
    ]
}
