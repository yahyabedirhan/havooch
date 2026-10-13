import Foundation
import ReviewWire

/// The help of `havooch`, all of it read from `CommandTable`: the top
/// help, a group's, a command's, and `help --json` with every command. So
/// the help never lists a command the code doesn't have.
enum Help {
    /// Where a person reads more than the help says.
    static let guide = "https://github.com/yahyabedirhan/havooch/blob/main/docs/guide.md"

    /// The usage lines the top help starts with, and an unknown command prints.
    static let usageLines = """
        Usage: havooch <command> [options]
               havooch <group> <verb> [options]
        """

    /// What `help` prints for `topic`: the top help with no words, else the
    /// command or the group they name; all of it as JSON with `json`.
    static func answer(_ topic: [String], json: Bool, groups: [CommandGroup] = CommandTable.groups) -> CommandResult {
        if topic.isEmpty {
            return json ? ConfigCommands.encoded(Table(groups: groups.map(Group.init))) : CommandResult(output: top(groups))
        }
        if let (command, rest) = CommandTable.find(topic), rest.isEmpty {
            return json ? ConfigCommands.encoded(Entry(command)) : CommandResult(output: help(for: command))
        }
        if topic.count == 1, let group = groups.first(where: { $0.name == topic[0] }) {
            return json ? ConfigCommands.encoded(Group(group)) : CommandResult(output: help(for: group))
        }
        let near = CommandTable.closest(to: topic).map { "; did you mean havooch help \($0)?" } ?? ""
        return .usage(
            "havooch help: no command or group `\(topic.joined(separator: " "))`\(near)\nusage: havooch help [<group> [<verb>]] [--json]"
        )
    }

    // MARK: - The top help

    /// `havooch --help`: the commands at the top level and the groups, by
    /// section, each with its summary.
    static func top(_ groups: [CommandGroup] = CommandTable.groups) -> String {
        let sections = HelpSection.allCases.map { section in (section, entries(in: section, groups)) }
        // The sections that list commands line up together; one of groups
        // only lines up on its own names, which are short.
        let listsCommands = sections.filter { $0.1.contains { $0.isCommand } }
        let commandWidth = listsCommands.flatMap(\.1).map(\.label.count).max() ?? 0
        let listed = sections.filter { !$0.1.isEmpty }.map { section, entries in
            let width = entries.contains { $0.isCommand } ? commandWidth : entries.map(\.label.count).max() ?? 0
            let lines = entries.map { "  " + $0.label.padding(toLength: width, withPad: " ", startingAt: 0) + "  " + $0.summary }
            return "\(section.heading):\n" + lines.joined(separator: "\n")
        }
        let window = groups.flatMap(\.commands).contains(where: \.takesWindow)
        let options = [
            "  --json          print JSON",
            window ? "  \(Command.windowOption) <id>   act on that window, not the key one" : nil,
            "  -h, --help      show help: havooch <group> --help, havooch <group> <verb> --help",
            "  --version       print the version",
        ].compactMap(\.self)
        return """
            \(AppIdentity.appName): a video player for giving feedback to agents.

            \(usageLines)

            \(listed.joined(separator: "\n\n"))

            Options:
            \(options.joined(separator: "\n"))

            Environment:
              \(SupportFolder.overrideVariable)   use this data folder, not yours
              \(MutedRun.variable)=1       play no sound in any window

            Exit codes: 0 done, 1 refused or failed, 2 wrong usage, 124 a wait ran out.

            Guide: \(guide)
            Agents: havooch help --json prints every command.
                    havooch setup install installs the havooch-mate skill.

            """
    }

    /// One line of the top help: a command or a group, and its summary.
    private struct Line {
        var label: String
        var summary: String
        var isCommand: Bool
    }

    /// The lines of `section`: its commands at the top level, then the
    /// commands of other groups listed there, then its groups.
    private static func entries(in section: HelpSection, _ groups: [CommandGroup]) -> [Line] {
        let commands = groups.flatMap { group in
            group.commands.filter { command in
                switch command.listing {
                case .withGroup: group.name == nil && group.section == section
                case .own(let own): own == section
                case .unlisted: false
                }
            }
        }
        let named = groups.filter { $0.name != nil && $0.section == section }
        return commands.map { Line(label: $0.briefUsage, summary: $0.summary, isCommand: true) }
            + named.map { Line(label: $0.name ?? "", summary: $0.summary, isCommand: false) }
    }

    // MARK: - A group's help

    /// `havooch player --help`: each command's usage with its summary under
    /// it. The lease is named for the whole group when each of its commands
    /// needs it, else on each command that does.
    static func help(for group: CommandGroup) -> String {
        let name = group.name ?? ""
        let operators = group.commands.filter { $0.role == .operator }.count
        let every = operators == group.commands.count
        let lease: String
        switch operators {
        case 0: lease = ""
        case group.commands.count: lease = " Needs the lease: havooch control take."
        default: lease = "\nThe commands marked (needs the lease) need it first: havooch control take."
        }
        let commands = group.commands.map { command in
            let marked = command.role == .operator && !every ? " (needs the lease)" : ""
            return "  havooch \(command.usage)\n      \(command.summary)\(marked)"
        }
        let options = (group.commands.contains(where: \.takesWindow) ? ["\(Command.windowOption) <id>"] : []) + ["--json"]
        return """
            \(sentence(group.summary))\(lease)

            Usage: havooch \(name) <verb> [options]

            Commands:
            \(commands.joined(separator: "\n"))

            Options: \(options.joined(separator: ", "))
            Run havooch \(name) <verb> --help for a command's details.

            """
    }

    // MARK: - A command's help

    /// `havooch player seek --help`: its summary, its usage, its examples,
    /// then what else it does, whether it needs the lease, and how it fails.
    static func help(for command: Command) -> String {
        let examples = command.examples.map { "  havooch \(command.name)" + ($0.isEmpty ? "" : " " + $0) }
        let lease = command.role == .operator ? "Needs the lease." : ""
        let more = [command.description, lease].filter { !$0.isEmpty }.joined(separator: " ")
        var parts = [
            sentence(command.summary),
            "Usage: " + usageLine(command),
            "Examples:\n" + examples.joined(separator: "\n"),
        ]
        if !more.isEmpty { parts.append(wrapped(more)) }
        if let codes = command.exitCodes { parts.append("Exit codes: \(codes)") }
        return parts.joined(separator: "\n\n") + "\n"
    }

    /// The command's whole usage line, with the options every command or
    /// its window takes: what wrong usage prints.
    static func usageLine(_ command: Command) -> String {
        "havooch \(command.usage)" + (command.takesWindow ? " [\(Command.windowOption) <id>]" : "") + " [--json]"
    }

    /// `text` in lines of at most `width` columns, broken between words.
    static func wrapped(_ text: String, width: Int = 80) -> String {
        var lines: [String] = []
        var line = ""
        for word in text.split(separator: " ") {
            if !line.isEmpty, line.count + 1 + word.count > width {
                lines.append(line)
                line = ""
            }
            line += (line.isEmpty ? "" : " ") + word
        }
        return (lines + [line]).joined(separator: "\n")
    }

    /// `summary` as a sentence: a capital first and a full stop last.
    private static func sentence(_ summary: String) -> String {
        summary.prefix(1).uppercased() + summary.dropFirst() + (summary.hasSuffix(".") ? "" : ".")
    }

    // MARK: - help --json

    /// Every group, in the help's order.
    private struct Table: Encodable {
        var groups: [Group]
    }

    private struct Group: Encodable {
        /// Absent for the commands at the top level.
        var name: String?
        var summary: String
        var section: String
        var commands: [Entry]

        init(_ group: CommandGroup) {
            name = group.name
            summary = group.summary
            section = group.section.rawValue
            commands = group.commands.map(Entry.init)
        }
    }

    private struct Entry: Encodable {
        var name: String
        var usage: String
        var summary: String
        var description: String
        var examples: [String]
        var role: String
        var options: [String]
        var takesWindow: Bool

        init(_ command: Command) {
            name = command.name
            usage = "havooch " + command.usage
            summary = command.summary
            description = command.description
            examples = command.examples.map { "havooch \(command.name)" + ($0.isEmpty ? "" : " " + $0) }
            role = Help.name(of: command.role)
            options = command.valuedOptions.union(command.flags).sorted()
            takesWindow = command.takesWindow
        }
    }

    /// The role as `help --json` names it.
    static func name(of role: ControlRequest.Role) -> String {
        switch role {
        case .free: "free"
        case .person: "person"
        case .operator: "operator"
        case .listener: "listener"
        }
    }
}
