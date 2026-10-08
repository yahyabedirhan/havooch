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
    /// Timed out with no result.
    public static let timedOutCode: Int32 = 2
    /// The arguments don't read.
    public static let usageCode: Int32 = 64

    /// Refused: one line on standard error, exit 1.
    public static func refused(_ message: String) -> CommandResult {
        CommandResult(error: message + "\n", exitCode: refusedCode)
    }

    /// The arguments don't read: lines on standard error, exit 64.
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
/// Exit codes: 0 done, 1 refused or failed, 2 timed out, 64 wrong usage.
public enum HavoochCLI {
    public static func run(_ arguments: [String], environment: CommandEnvironment) -> CommandResult {
        // `--json` is an option anywhere before `--`; after it, it's a word.
        let end = arguments.firstIndex(of: Arguments.optionsEnd) ?? arguments.endIndex
        let json = arguments[..<end].contains("--json")
        let arguments = arguments[..<end].filter { $0 != "--json" } + arguments[end...]
        // Help is asked for before the command's name: after it, `-h` and
        // `--help` may be a comment's text.
        let beforeTheName = arguments.prefix { $0.hasPrefix("-") && $0 != Arguments.optionsEnd }
        if beforeTheName.contains("--help") || beforeTheName.contains("-h") {
            return CommandResult(output: CommandTable.usageText)
        }
        // The app's version, which this command was built with; no app is asked.
        if beforeTheName.contains("--version") {
            // As the app's JSON is printed: readable, one key per line.
            return CommandResult(output: json ? "{\n  \"version\" : \"\(Version.app)\"\n}\n" : Version.app + "\n")
        }
        guard !arguments.isEmpty else { return .usage(CommandTable.usageText) }
        guard let (command, rest) = CommandTable.find(arguments) else {
            return .usage("havooch: unknown command `\(arguments.prefix(2).joined(separator: " "))`\n\n" + CommandTable.usageText)
        }
        var invocation: Invocation
        do throws(UsageError) {
            let valued = command.takesWindow ? command.valuedOptions.union([Command.windowOption]) : command.valuedOptions
            let parsed = try Arguments(rest, valued: valued, flags: command.flags)
            invocation = try command.parse(parsed, environment)
            // The window `--window` names, unless the command named one itself.
            if command.takesWindow, case .send(let request, .none) = invocation, let window = parsed.options[Command.windowOption] {
                invocation = .send(request, window: window)
            }
        } catch {
            return .usage("havooch \(command.name): \(error.message)\nusage: havooch \(command.synopsis)")
        }
        return run(invocation, json: json, environment: environment)
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
        let app = AppCommands.Context(support: support, client: client, launcher: environment.launcher, pause: environment.pause)
        switch invocation {
        case .send(let request, let window): return result(of: client.send(request, window: window))
        case .appStatus: return AppCommands.status(app)
        case .appOpen(let demo): return AppCommands.open(demo: demo, app)
        case .appQuit: return AppCommands.quit(app)
        case .open(let file): return OpenCommand.run(file, app)
        case .wait(let timeout): return ListenerCommands.wait(timeout: timeout, client: client, environment: environment)
        case .configPath: return ConfigCommands.path(json: json, environment: environment)
        case .configCheck: return ConfigCommands.check(json: json, environment: environment)
        }
    }

    static let notRunning = "\(AppIdentity.appName) isn't running; run `havooch app open`"

    /// What a reply, or the failure to get one, prints and how it exits.
    static func result(of answer: Result<ControlReply, ControlClient.Failure>) -> CommandResult {
        switch answer {
        case .success(let reply) where reply.ok:
            return CommandResult(output: reply.output, error: reply.error)
        case .success(let reply) where reply.timedOut == true:
            // A held request (an `ask`) waited its whole time: nothing to print.
            return CommandResult(exitCode: CommandResult.timedOutCode)
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
