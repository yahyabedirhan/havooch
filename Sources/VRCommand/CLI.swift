import Foundation
import VRLease
import VRWire

/// What a command reads from where it runs. The real one is `live()`;
/// tests give a fake transport and launcher, and a support folder of their own.
public struct CommandEnvironment: Sendable {
    public var variables: [String: String]
    public var workingDirectory: URL
    public var processes: any ProcessTable
    public var transport: any ControlTransport
    public var launcher: any AppLaunching
    /// The app bundle the command sits in (`…/Contents/Helpers/video-review`
    /// gives `…`), which `app open` starts; nil outside a bundle.
    public var bundle: URL?
    /// The real support folder: the sockets and the demo pointer.
    public var support: URL
    /// Waits between two looks at an app that starts or quits.
    public var pause: @Sendable (TimeInterval) -> Void

    public init(
        variables: [String: String],
        workingDirectory: URL,
        processes: any ProcessTable,
        transport: any ControlTransport,
        launcher: any AppLaunching,
        bundle: URL?,
        support: URL,
        pause: @escaping @Sendable (TimeInterval) -> Void
    ) {
        self.variables = variables
        self.workingDirectory = workingDirectory
        self.processes = processes
        self.transport = transport
        self.launcher = launcher
        self.bundle = bundle
        self.support = support
        self.pause = pause
    }

    /// The environment of the running `video-review` executable.
    public static func live() -> CommandEnvironment {
        CommandEnvironment(
            variables: ProcessInfo.processInfo.environment,
            workingDirectory: URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true),
            processes: SystemProcessTable(),
            transport: UnixSocketTransport(),
            launcher: WorkspaceLauncher(),
            bundle: enclosingBundle(of: Bundle.main.executableURL),
            support: SupportFolder.real(),
            pause: { Thread.sleep(forTimeInterval: $0) }
        )
    }

    /// The app bundle whose `Contents/Helpers` holds `executable`, if any.
    static func enclosingBundle(of executable: URL?) -> URL? {
        guard let helpers = executable?.resolvingSymlinksInPath().deletingLastPathComponent(),
              helpers.lastPathComponent == "Helpers"
        else { return nil }
        let contents = helpers.deletingLastPathComponent()
        let bundle = contents.deletingLastPathComponent()
        guard contents.lastPathComponent == "Contents", bundle.pathExtension == "app" else { return nil }
        return bundle
    }
}

public enum CLI {
    /// Everything the executable does: the arguments parsed through the
    /// command table, the request sent as this command's holder, the
    /// reply's output and error to print and the exit code.
    public static func run(arguments: [String], environment: CommandEnvironment) -> CommandResult {
        // `--json` is accepted anywhere on the line.
        let json = arguments.contains("--json")
        let words = arguments.filter { $0 != "--json" }
        if words.isEmpty {
            return CommandResult(error: CommandTable.help, exitCode: CommandResult.usage)
        }
        if words == ["help"] || words.contains("--help") || words.contains("-h") {
            return CommandResult(output: CommandTable.help)
        }
        guard let command = CommandTable.match(words) else {
            let named = words.prefix(2).prefix { !$0.hasPrefix("--") }.joined(separator: " ")
            return CommandResult(error: "video-review: unknown command `\(named)`\n" + CommandTable.help, exitCode: CommandResult.usage)
        }
        var rest = Arguments(Array(words.dropFirst(command.words.count)), workingDirectory: environment.workingDirectory)
        let invocation: Invocation
        do throws(UsageError) {
            invocation = try command.parse(&rest)
            try rest.finish()
        } catch {
            return CommandResult(
                error: "video-review \(command.name): \(error.line)\nusage: video-review \(command.usage)\n",
                exitCode: CommandResult.usage
            )
        }

        let holder = Holder.find(
            variables: environment.variables, workingDirectory: environment.workingDirectory, processes: environment.processes
        )
        let client = ControlClient(
            socket: ControlSocket.locate(support: environment.support), holder: holder, transport: environment.transport
        )
        let app = AppCommand(
            support: environment.support, client: client, launcher: environment.launcher,
            bundle: environment.bundle, pause: environment.pause, json: json
        )
        switch invocation {
        case .send(let request):
            let result = AppCommand.result(of: client.send(request, json: json))
            // A `wait` the app answers with nothing ran out: the reply keeps
            // its four fields, and the command, which knows what it sent, says so.
            if case .wait(let timeout) = request, result.exitCode == CommandResult.success, result.output.isEmpty {
                return CommandResult(error: "no batch within \(timeout ?? 0) s\n", exitCode: CommandResult.ranOut)
            }
            return result
        case .appStatus: return app.status()
        case .appOpen(let demo): return app.open(demo: demo)
        case .appQuit: return app.quit()
        }
    }
}
