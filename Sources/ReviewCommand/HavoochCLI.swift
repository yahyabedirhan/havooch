import Foundation
import ReviewLease
import ReviewWire

/// What a command run prints and how it exits: the `havooch`
/// executable writes `output` to standard output and `error` to standard
/// error, then exits with `exitCode`.
public struct CommandResult: Equatable, Sendable {
    public var output: String
    public var error: String
    public var exitCode: Int32

    public init(output: String = "", error: String = "", exitCode: Int32 = 0) {
        self.output = output
        self.error = error
        self.exitCode = exitCode
    }

    /// Refused or failed: the lease is in use, the app isn't running, a
    /// file doesn't play.
    public static let refusedCode: Int32 = 1
    /// A wait ran out with no result: `wait`, `ask` or `control take`
    /// with `--timeout`.
    public static let timedOutCode: Int32 = 124
    /// The arguments don't read.
    public static let usageCode: Int32 = 2

    /// Refused: one line on standard error, exit 1.
    public static func refused(_ message: String) -> CommandResult {
        CommandResult(error: message + "\n", exitCode: refusedCode)
    }

    /// The arguments don't read: lines on standard error, exit 2.
    public static func usage(_ message: String) -> CommandResult {
        CommandResult(error: message + "\n", exitCode: usageCode)
    }
}

/// Everything a command run takes from outside, so tests replace all of it.
public struct CommandEnvironment: Sendable {
    public var variables: [String: String]
    /// The folder the command runs in: relative paths are taken against it,
    /// since the app runs in another one.
    public var workingDirectory: URL
    public var processes: any ProcessTable
    public var transport: any ControlTransport
    public var launcher: any AppLaunching
    /// Waits between two looks at the app while it starts or quits.
    public var pause: @Sendable (TimeInterval) -> Void
    /// The time, which `wait --timeout` counts its seconds by.
    public var now: @Sendable () -> Date

    public init(
        variables: [String: String],
        workingDirectory: URL,
        processes: any ProcessTable,
        transport: any ControlTransport,
        launcher: any AppLaunching,
        pause: @escaping @Sendable (TimeInterval) -> Void,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.variables = variables
        self.workingDirectory = workingDirectory
        self.processes = processes
        self.transport = transport
        self.launcher = launcher
        self.pause = pause
        self.now = now
    }

    /// The real environment of the `havooch` executable at
    /// `executable`.
    public static func live(executable: URL?) -> CommandEnvironment {
        CommandEnvironment(
            variables: ProcessInfo.processInfo.environment,
            workingDirectory: URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true),
            processes: SystemProcessTable(),
            transport: UnixSocketTransport(),
            launcher: WorkspaceLauncher(command: executable),
            pause: { Thread.sleep(forTimeInterval: $0) }
        )
    }
}

/// The `havooch` command: its arguments read through `CommandTable`,
/// one request sent to the app, the reply printed, the exit code picked.
/// Exit codes: 0 done, 1 refused or failed, 2 wrong usage, 124 a wait ran out.
public enum HavoochCLI {
    public static func run(_ arguments: [String], environment: CommandEnvironment) -> CommandResult {
        switch read(arguments, environment: environment) {
        case .answered(let result): result
        case .invocation(_, let invocation, let json): run(invocation, json: json, environment: environment)
        }
    }

    /// What a command line comes to before anything is asked: an answer
    /// the command gives itself (help, the version, wrong usage), or the
    /// command found and what it asks for.
    enum Reading {
        case answered(CommandResult)
        case invocation(Command, Invocation, json: Bool)
    }

    /// Reads `arguments` through `CommandTable`, the one path from a
    /// command line to what it asks for.
    static func read(_ arguments: [String], environment: CommandEnvironment) -> Reading {
        // `--json` is an option anywhere before `--`; after it, it's a word.
        let end = arguments.firstIndex(of: Arguments.optionsEnd) ?? arguments.endIndex
        let json = arguments[..<end].contains("--json")
        let arguments = arguments[..<end].filter { $0 != "--json" } + arguments[end...]
        let beforeTheName = arguments.prefix { $0.hasPrefix("-") && $0 != Arguments.optionsEnd }
        if beforeTheName.contains(where: isHelp) {
            // The help of the words that follow, or the top help.
            let topic = Array(arguments.dropFirst(beforeTheName.count).prefix { !$0.hasPrefix("-") })
            let answer = Help.answer(topic, json: false)
            return .answered(answer.exitCode == 0 ? answer : CommandResult(output: Help.top()))
        }
        // The app's version, which this command was built with; no app is asked.
        if beforeTheName.contains("--version") {
            // As the app's JSON is printed: readable, one key per line.
            return .answered(CommandResult(output: json ? "{\n  \"version\" : \"\(Version.app)\"\n}\n" : Version.app + "\n"))
        }
        guard let first = arguments.first else { return .answered(CommandResult(output: Help.top())) }
        guard let (command, rest) = CommandTable.find(arguments) else {
            if let group = CommandTable.group(named: first), arguments.count == 1 || isHelp(arguments[1]) {
                return .answered(CommandResult(output: Help.help(for: group)))
            }
            return .answered(unknown(arguments))
        }
        // Help counts right after the command's name; later, and after
        // `--`, `-h` and `--help` may be a message's text.
        if let word = rest.first, isHelp(word) { return .answered(CommandResult(output: Help.help(for: command))) }
        do throws(UsageError) {
            let valued = command.takesWindow ? command.valuedOptions.union([Command.windowOption]) : command.valuedOptions
            let parsed = try Arguments(rest, valued: valued, flags: command.flags)
            var invocation = try command.parse(parsed, environment)
            // The window `--window` names, unless the command named one itself.
            if command.takesWindow, case .send(let request, .none) = invocation, let window = parsed.options[Command.windowOption] {
                invocation = .send(request, window: window)
            }
            return .invocation(command, invocation, json: json)
        } catch {
            return .answered(.usage(
                "havooch \(command.name): \(error.message)\nusage: \(Help.usageLine(command))\nrun havooch \(command.name) --help for details"
            ))
        }
    }

    /// Whether `argument` asks for help.
    private static func isHelp(_ argument: String) -> Bool {
        argument == "-h" || argument == "--help"
    }

    /// No command starts `arguments`: it names the closest one, when one
    /// is near, and the usage lines.
    private static func unknown(_ arguments: [String]) -> CommandResult {
        let written = Array(arguments.prefix { !$0.hasPrefix("-") }.prefix(2))
        let closest = CommandTable.closest(to: written)
        // A group's word and the verb after it, or as many words as the
        // closest name has, else the one word.
        let inGroup = written.first.flatMap(CommandTable.group(named:)) != nil
        let length = inGroup || closest?.contains(" ") == true ? 2 : 1
        let named = arguments.prefix(length).joined(separator: " ")
        let near = closest.map { "; did you mean havooch \($0)?" } ?? ""
        return .usage("havooch: unknown command `\(named)`\(near)\n\(Help.usageLines)\nrun havooch --help for every command")
    }

    /// Runs `invocation` against the app the environment's support folder
    /// (and its demo pointer) leads to.
    static func run(_ invocation: Invocation, json: Bool, environment: CommandEnvironment) -> CommandResult {
        let support = SupportFolder.app(environment: environment.variables)
        let client = ControlClient(
            socket: ControlSocket.locate(support: support),
            holder: Holder.find(
                variables: environment.variables, workingDirectory: environment.workingDirectory,
                processes: environment.processes
            ),
            json: json,
            transport: environment.transport
        )
        let app = AppCommands.Context(
            support: support, client: client, launcher: environment.launcher, pause: environment.pause,
            muted: MutedRun.isMuted(environment: environment.variables)
        )
        switch invocation {
        case .send(let request, let window): return result(of: client.send(request, window: window))
        case .appStatus: return AppCommands.status(app)
        case .appOpen(let demo): return AppCommands.open(demo: demo, app)
        case .appQuit: return AppCommands.quit(app)
        case .open(let file, let project): return OpenCommand.run(file, project: project, app)
        case .wait(let timeout, let video, let project):
            return ListenerCommands.wait(timeout: timeout, video: video, project: project, client: client, environment: environment)
        case .projectNew(let slug, let video, let title): return ProjectCommands.new(slug: slug, video: video, title: title, app)
        case .projectAdd(let slug, let video, let label): return ProjectCommands.add(slug: slug, video: video, label: label, app)
        case .projectList: return ProjectCommands.list(json: json, environment: environment)
        case .configPath: return ConfigCommands.path(json: json, environment: environment)
        case .configCheck: return ConfigCommands.check(json: json, environment: environment)
        case .help(let topic): return Help.answer(topic, json: json)
        }
    }

    static let notRunning = "\(AppIdentity.appName) isn't running; run `havooch app open`"

    /// What a reply, or the failure to get one, prints and how it exits.
    static func result(of answer: Result<ControlReply, ControlClient.Failure>) -> CommandResult {
        switch answer {
        case .success(let reply) where reply.ok:
            return CommandResult(output: reply.output, error: reply.error)
        case .success(let reply) where reply.timedOut == true:
            // A held request waited its whole time: an `ask` has nothing to
            // print, a `control take` says who still holds the lease.
            return CommandResult(error: reply.error.isEmpty ? "" : reply.error + "\n", exitCode: CommandResult.timedOutCode)
        case .success(let reply):
            return .refused(reply.error.isEmpty ? "\(AppIdentity.appName) refused without saying why" : reply.error)
        case .failure(.notRunning):
            return .refused(notRunning)
        case .failure(.timedOut(let seconds)):
            return .refused("\(AppIdentity.appName) didn't answer within \(Int(seconds)) seconds")
        case .failure(.failed(let why)):
            return .refused("couldn't ask \(AppIdentity.appName): \(why)")
        }
    }
}
