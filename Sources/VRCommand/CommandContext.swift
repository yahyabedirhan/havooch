import Foundation
import VRLease
import VRWire

/// What the command reads from outside itself: the real ones in `main.swift`
/// (`system()`), fakes in tests.
public struct CommandEnvironment: Sendable {
    public var variables: [String: String]
    public var workingDirectory: URL
    public var transport: any ControlTransport
    public var launcher: any AppLaunching
    public var processes: any ProcessTable
    /// Waits between two looks at the app while it starts or quits.
    public var pause: @Sendable (TimeInterval) -> Void

    public init(
        variables: [String: String],
        workingDirectory: URL,
        transport: any ControlTransport,
        launcher: any AppLaunching,
        processes: any ProcessTable,
        pause: @escaping @Sendable (TimeInterval) -> Void
    ) {
        self.variables = variables
        self.workingDirectory = workingDirectory
        self.transport = transport
        self.launcher = launcher
        self.processes = processes
        self.pause = pause
    }

    /// This process's environment, the socket and Launch Services.
    public static func system() -> CommandEnvironment {
        CommandEnvironment(
            variables: ProcessInfo.processInfo.environment,
            workingDirectory: URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true),
            transport: UnixSocketTransport(),
            launcher: WorkspaceLauncher(),
            processes: SystemProcessTable(),
            pause: { Thread.sleep(forTimeInterval: $0) }
        )
    }
}

/// What one invocation runs with: the normal support folder, the client
/// asking the app at the socket found from it, and whether `--json` was
/// given.
public struct CommandContext: Sendable {
    /// The app's normal support folder, where `app open --demo` leaves its
    /// `DemoPointer`.
    public var support: URL
    public var client: ControlClient
    public var launcher: any AppLaunching
    public var pause: @Sendable (TimeInterval) -> Void
    public var workingDirectory: URL
    /// `--json`: the app answers with one JSON object.
    public var json: Bool

    public init(environment: CommandEnvironment, json: Bool) {
        support = AppIdentity.supportFolder(variables: environment.variables)
        client = ControlClient(
            socket: ControlSocket.locate(support: support),
            holder: Holder.find(
                variables: environment.variables,
                workingDirectory: environment.workingDirectory,
                processes: environment.processes
            ),
            transport: environment.transport
        )
        launcher = environment.launcher
        pause = environment.pause
        workingDirectory = environment.workingDirectory
        self.json = json
    }

    /// The same client, asking at `socket`.
    func client(at socket: URL) -> ControlClient {
        var client = client
        client.socket = socket
        return client
    }

    /// Sends `request` to the app and turns its reply into what to print.
    public func send(_ request: ControlRequest) -> CommandResult {
        Self.result(of: client.send(request, json: json))
    }

    /// What a command whose arguments were read into `parsed` prints: the
    /// app's answer to the request, or what parsing already decided.
    func send(_ parsed: Result<ControlRequest, CommandResult>) -> CommandResult {
        switch parsed {
        case .success(let request): send(request)
        case .failure(let result): result
        }
    }

    static let notRunning = "video-review isn't running; `video-review app open`"

    /// What a reply, or the failure to get one, prints and how it exits.
    static func result(of answer: Result<ControlReply, ControlClient.Failure>) -> CommandResult {
        switch answer {
        case .success(let reply) where reply.ok:
            return CommandResult(output: reply.output, error: reply.error)
        case .success(let reply):
            return .failed(reply.error.isEmpty ? "video-review refused without saying why" : reply.error)
        case .failure(.notRunning):
            return .failed(notRunning)
        case .failure(.timedOut(let seconds)):
            return .failed("video-review didn't answer within \(Int(seconds)) seconds")
        case .failure(.failed(let why)):
            return .failed("couldn't ask video-review: \(why)")
        }
    }
}
