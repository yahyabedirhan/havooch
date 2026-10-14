import Foundation
import ReviewWire

enum Invocation: Equatable, Sendable {
    case send(ControlRequest, window: String? = nil)
    case appStatus
    case appOpen(demo: URL?)
    case appQuit
    case open(URL, project: String? = nil)
    case wait(timeout: Int?, video: URL? = nil, project: String? = nil)
    case projectNew(slug: String, video: URL, title: String?)
    case projectAdd(slug: String, video: URL, label: String?)
    case projectList
    case configPath
    case configCheck
    case help([String])

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
        case .projectList, .configPath, .configCheck, .help: .free
        }
    }
}

struct UsageError: Error, Equatable {
    var message: String

    init(_ message: String) {
        self.message = message
    }
}

struct Arguments: Equatable {
    var words: [String] = []
    var options: [String: String] = [:]
    var repeated: [String: [String]] = [:]
    var flags: Set<String> = []

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

    static let optionsEnd = "--"

    static func isOption(_ argument: String) -> Bool {
        argument.hasPrefix("--") && !argument.contains(where: \.isWhitespace)
    }

    func one(_ name: String) throws(UsageError) -> String {
        try exactly([name])[0]
    }

    func exactly(_ names: [String]) throws(UsageError) -> [String] {
        guard words.count >= names.count else { throw UsageError("missing \(names[words.count])") }
        guard words.count == names.count else { throw UsageError("unexpected `\(words[names.count])`") }
        return words
    }

    func none() throws(UsageError) {
        if let word = words.first { throw UsageError("unexpected `\(word)`") }
    }
}

enum HelpSection: String, CaseIterable, Sendable {
    case feedback
    case look
    case drive

    var heading: String {
        switch self {
        case .feedback: "Get feedback"
        case .look: "Look"
        case .drive: "Drive the app (take the lease first: havooch control take)"
        }
    }
}

struct Command: Sendable {
    enum Listing: Sendable {
        case withGroup
        case own(HelpSection)
        case unlisted
    }

    var name: String
    var arguments: String
    var summary: String
    var description: String
    var examples: [String]
    var role: ControlRequest.Role
    var exitCodes: String?
    var brief: String?
    var listing: Listing
    var valuedOptions: Set<String>
    var flags: Set<String>
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

    static let windowOption = "--window"

    var usage: String {
        arguments.isEmpty ? name : name + " " + arguments
    }

    var briefUsage: String {
        let words = brief.map { $0.split(separator: " ").map(String.init) }
            ?? Array(arguments.split(separator: " ").map(String.init).prefix { !$0.hasPrefix("--") && !$0.hasPrefix("[--") })
        return ([name] + words).joined(separator: " ")
    }

    func onAWindow() -> Command {
        var command = self
        command.takesWindow = true
        return command
    }
}

struct CommandGroup: Sendable {
    var name: String?
    var summary: String
    var section: HelpSection
    var commands: [Command]
}

enum CommandTable {
    static let groups: [CommandGroup] = [
        ListenerCommands.group, LookCommands.group, ProjectCommands.group, AppCommands.group, WindowCommands.group,
        ControlCommands.group, PlayerCommands.group, MessageCommands.group, ContextCommands.group, ThreadCommands.group,
        PopoverCommands.group, ComposerCommands.group, SidebarCommands.group, VersionCommands.group,
        CompareCommands.group, ThemeCommands.group, ConfigCommands.group, SetupCommands.group, ConnectCommands.group,
        TourCommands.group, FirstRunCommands.group,
    ]

    static let commands: [Command] = groups.flatMap(\.commands)

    static func find(_ arguments: [String]) -> (Command, [String])? {
        for length in [2, 1] where arguments.count >= length {
            let name = arguments.prefix(length).joined(separator: " ")
            if let command = commands.first(where: { $0.name == name }) {
                return (command, Array(arguments.dropFirst(length)))
            }
        }
        return nil
    }

    static func group(named name: String) -> CommandGroup? {
        groups.first { $0.name == name }
    }

    static func closest(to words: [String]) -> String? {
        let names = commands.map(\.name) + groups.compactMap(\.name)
        let inGroup = words.first.flatMap(group(named:)) != nil
        let written = [words.prefix(2).joined(separator: " ")] + (inGroup || words.count < 2 ? [] : [words[0]])
        var best: (name: String, distance: Int)?
        for written in written where !written.isEmpty {
            let most = max(1, written.count / 5)
            for name in names {
                let distance = editDistance(written, name)
                if distance <= most, distance < best?.distance ?? .max { best = (name, distance) }
            }
        }
        return best?.name
    }

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
