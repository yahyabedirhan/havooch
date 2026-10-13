import Foundation
import ReviewWire

/// What a command line asks for.
enum Invocation: Equatable, Sendable {
    /// A request the running app answers.
    case send(ControlRequest, window: String? = nil)
    /// `app status`: answered without the app when it isn't running.
    case appStatus
    /// `app open`: launch the app unless it runs on the data asked for, on
    /// the demo's support folder when there is one.
    case appOpen(demo: URL?)
    /// `app quit`: ask the app to quit, then wait until it's gone.
    case appQuit
    /// `open <path> [--project <slug>]`: the video at the absolute `file`
    /// opened in front, in the project `project` when it's set, with the
    /// app launched first when it doesn't run.
    case open(URL, project: String? = nil)
    /// `wait`: hold a request until a send of the review the video at the
    /// absolute `video` path opens in, or of the project `project`, else
    /// of the key window's, is made, for `timeout` seconds or with no
    /// limit, connecting again while the app isn't running.
    case wait(timeout: Int?, video: URL? = nil, project: String? = nil)
    /// `project new`: through the app, launched in the background when it
    /// doesn't run.
    case projectNew(slug: String, video: URL, title: String?)
    /// `project add`: through the app, launched in front when it doesn't run.
    case projectAdd(slug: String, video: URL, label: String?)
    /// `project list`: answered without the app.
    case projectList
    /// `config path`: answered without the app.
    case configPath
    /// `config check`: answered without the app.
    case configCheck
    /// `help [<group> [<verb>]]`: the help the words name, from the table.
    case help([String])

    /// The role of what the command line asks for, as the app reads it: a
    /// request's own role, and for what the command answers itself, the
    /// role of the request it stands for.
    var role: ControlRequest.Role {
        switch self {
        case .send(let request, _): request.role
        case .appStatus: ControlRequest.appStatus.role
        case .appOpen: ControlRequest.appOpen.role
        case .appQuit: ControlRequest.appQuit.role
        case .open(let file, let project): ControlRequest.open(path: file.path, project: project).role
        case .wait(let timeout, _, let project): ControlRequest.wait(timeoutSeconds: timeout, project: project).role
        case .projectNew(let slug, let video, let title): ControlRequest.projectNew(slug: slug, path: video.path, title: title).role
        case .projectAdd(let slug, let video, let label): ControlRequest.projectAdd(slug: slug, path: video.path, label: label).role
        // Read from the disk or the table: nothing anyone sees changes.
        case .projectList, .configPath, .configCheck, .help: .free
        }
    }
}

/// Arguments that don't read, as one line.
struct UsageError: Error, Equatable {
    var message: String

    init(_ message: String) {
        self.message = message
    }
}

/// A command's arguments, split into the words and the `--options`.
struct Arguments: Equatable {
    var words: [String] = []
    /// Each valued option written, with its value; the last one when it's
    /// written more than once.
    var options: [String: String] = [:]
    /// Every value of each valued option, in the order written: a
    /// repeatable option such as `ask --choice` reads all of them.
    var repeated: [String: [String]] = [:]
    /// The `--flags` written: options with no value.
    var flags: Set<String> = []

    /// Reads `raw`; `valued` names the options the command takes, each
    /// with a value after it, and `flags` those with none. Any other
    /// `--option` is refused. A text may look like an option: an argument
    /// with a space in it is a word, and so is every argument after `--`.
    init(_ raw: [String], valued: Set<String>, flags known: Set<String> = []) throws(UsageError) {
        var rest = raw[...]
        var optionsEnded = false
        while let argument = rest.popFirst() {
            if !optionsEnded, argument == Self.optionsEnd {
                optionsEnded = true
                continue
            }
            guard !optionsEnded, Self.isOption(argument) else {
                words.append(argument)
                continue
            }
            if known.contains(argument) {
                flags.insert(argument)
                continue
            }
            guard valued.contains(argument) else { throw UsageError("unknown option `\(argument)`") }
            guard let value = rest.popFirst() else { throw UsageError("`\(argument)` needs a value") }
            options[argument] = value
            repeated[argument, default: []].append(value)
        }
    }

    /// The argument that ends the options: every argument after it is a word.
    static let optionsEnd = "--"

    /// Whether `argument` is written as an option: `--name`. No option's
    /// name has a space in it, so a sentence that starts with `--` is a word.
    static func isOption(_ argument: String) -> Bool {
        argument.hasPrefix("--") && !argument.contains(where: \.isWhitespace)
    }

    /// The only word, which the command needs: `name` says what it is.
    func one(_ name: String) throws(UsageError) -> String {
        try exactly([name])[0]
    }

    /// The words the command needs, one per name in `names`, in order.
    func exactly(_ names: [String]) throws(UsageError) -> [String] {
        guard words.count >= names.count else { throw UsageError("missing \(names[words.count])") }
        guard words.count == names.count else { throw UsageError("unexpected `\(words[names.count])`") }
        return words
    }

    /// Refuses any word: the command takes none.
    func none() throws(UsageError) {
        if let word = words.first { throw UsageError("unexpected `\(word)`") }
    }
}

/// Where the top help lists a group, or a command.
enum HelpSection: String, CaseIterable, Sendable {
    case feedback
    case look
    case drive

    /// The section's heading in the top help.
    var heading: String {
        switch self {
        case .feedback: "Get feedback"
        case .look: "Look"
        case .drive: "Drive the app (take the lease first: havooch control take)"
        }
    }
}

/// One command of `havooch`: its name, what it takes, what the help says
/// of it, and how its arguments become an `Invocation`.
struct Command: Sendable {
    /// Where the top help lists a command.
    enum Listing: Sendable {
        /// With its group: on its own line for a command at the top level,
        /// under the group's line for a group's command.
        case withGroup
        /// On its own line in `section`, though its group is listed elsewhere.
        case own(HelpSection)
        /// Not in the top help.
        case unlisted
    }

    /// The words that name it: `player seek`. Its usage, its examples and
    /// its help all read the name from here.
    var name: String
    /// What follows the name: `<seconds|m:ss>`; empty for none.
    var arguments: String
    /// One line, starting with a verb, saying what the command achieves.
    var summary: String
    /// What else a caller should know: the UI action it matches, what it
    /// prints, its limits. Empty for nothing more.
    var description: String
    /// Each example's words after `havooch <name>`, as a shell reads them.
    var examples: [String]
    /// Who may run it: the role of the request it sends.
    var role: ControlRequest.Role
    /// The exit codes past 0 a caller should expect, in words; nil for the
    /// usual ones.
    var exitCodes: String?
    /// The words after the name in the top help, when the arguments up to
    /// the first option don't say it well.
    var brief: String?
    var listing: Listing
    /// The `--options` it takes, each with a value.
    var valuedOptions: Set<String>
    /// The `--flags` it takes, each with no value.
    var flags: Set<String>
    /// Whether it acts on one window and takes `--window <id>`, the key
    /// window without it.
    var takesWindow = false
    var parse: @Sendable (Arguments, CommandEnvironment) throws(UsageError) -> Invocation

    init(
        name: String, arguments: String = "", summary: String, description: String = "", examples: [String],
        role: ControlRequest.Role, exitCodes: String? = nil, brief: String? = nil, listing: Listing = .withGroup,
        valuedOptions: Set<String> = [], flags: Set<String> = [],
        parse: @escaping @Sendable (Arguments, CommandEnvironment) throws(UsageError) -> Invocation
    ) {
        self.name = name
        self.arguments = arguments
        self.summary = summary
        self.description = description
        self.examples = examples
        self.role = role
        self.exitCodes = exitCodes
        self.brief = brief
        self.listing = listing
        self.valuedOptions = valuedOptions
        self.flags = flags
        self.parse = parse
    }

    /// The option that names the window a command acts on.
    static let windowOption = "--window"

    /// The name with its arguments: `player seek <seconds|m:ss>`.
    var usage: String {
        arguments.isEmpty ? name : name + " " + arguments
    }

    /// The name with the arguments up to the first option, as the top help
    /// lists it: `ask <thread> <question>`.
    var briefUsage: String {
        let words = brief.map { $0.split(separator: " ").map(String.init) }
            ?? Array(arguments.split(separator: " ").map(String.init).prefix { !$0.hasPrefix("--") && !$0.hasPrefix("[--") })
        return ([name] + words).joined(separator: " ")
    }

    /// The same command, acting on the window `--window` names.
    func onAWindow() -> Command {
        var command = self
        command.takesWindow = true
        return command
    }
}

/// A group of commands, as the help lists them: `havooch player ...`. The
/// commands at the top level are in groups with no name.
struct CommandGroup: Sendable {
    /// The first word of its commands; nil for commands at the top level.
    var name: String?
    /// What its commands do, in a few words starting with a verb.
    var summary: String
    var section: HelpSection
    var commands: [Command]
}

/// The commands of `havooch`, in groups, in the order the help lists them.
/// A new command is a `Command` in its group's list, each group in its own
/// file. `--json` is accepted on every command.
enum CommandTable {
    static let groups: [CommandGroup] = [
        ListenerCommands.group, LookCommands.group, ProjectCommands.group, AppCommands.group, WindowCommands.group,
        ControlCommands.group, PlayerCommands.group, MessageCommands.group, ContextCommands.group, ThreadCommands.group,
        PopoverCommands.group, ComposerCommands.group, SidebarCommands.group, VersionCommands.group,
        CompareCommands.group, ThemeCommands.group, ConfigCommands.group, SetupCommands.group, ConnectCommands.group,
        TourCommands.group, FirstRunCommands.group,
    ]

    /// Every command, in the help's order.
    static let commands: [Command] = groups.flatMap(\.commands)

    /// The command `arguments` start with, and the arguments after its name.
    static func find(_ arguments: [String]) -> (Command, [String])? {
        // The longest name first: `app status` before a one-word command.
        for length in [2, 1] where arguments.count >= length {
            let name = arguments.prefix(length).joined(separator: " ")
            if let command = commands.first(where: { $0.name == name }) {
                return (command, Array(arguments.dropFirst(length)))
            }
        }
        return nil
    }

    /// The group named `name`.
    static func group(named name: String) -> CommandGroup? {
        groups.first { $0.name == name }
    }

    /// The command or group named closest to `words`, when one is near
    /// enough to be a slip: `plyer play` names `player play`.
    static func closest(to words: [String]) -> String? {
        let names = commands.map(\.name) + groups.compactMap(\.name)
        // The two words first, so a slip in a group's word names the
        // command; after a group's own word, only a verb can be the slip.
        let inGroup = words.first.flatMap(group(named:)) != nil
        let written = [words.prefix(2).joined(separator: " ")] + (inGroup || words.count < 2 ? [] : [words[0]])
        var best: (name: String, distance: Int)?
        for written in written where !written.isEmpty {
            // A slip is about one letter in five, and at least one.
            let most = max(1, written.count / 5)
            for name in names {
                let distance = editDistance(written, name)
                if distance <= most, distance < best?.distance ?? .max { best = (name, distance) }
            }
        }
        return best?.name
    }

    /// How many letters to add, remove or change to make `a` into `b`.
    static func editDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        var previous = Array(0...b.count)
        for (i, letter) in a.enumerated() {
            var current = [i + 1]
            for (j, other) in b.enumerated() {
                current.append(min(previous[j + 1] + 1, current[j] + 1, previous[j] + (letter == other ? 0 : 1)))
            }
            previous = current
        }
        return previous[b.count]
    }
}
