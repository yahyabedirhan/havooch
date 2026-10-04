import Foundation
import VRLease
import VRWire

/// `video-review app …`: `status` asks the running app; `open` launches it
/// first when it doesn't run (through `AppLaunching`), on a demo folder with
/// `--demo`; `quit` asks it to quit and waits until it's gone. An `open`
/// that quits one app to launch another hands the quit app's lease over to
/// the launched one, so the opener keeps it, cap and all.
public enum AppCommand {
    public static let entry = CommandTable.Entry(
        name: "app",
        summary: "open [--demo <folder>] | quit | status: start, stop or ask about the app",
        run: run
    )

    /// What a command line asks for.
    enum Invocation: Equatable {
        /// `app open`: launch the app unless it runs, then wait until it
        /// answers. With a demo folder, the app runs on that folder's own
        /// support folder; without one, a demo that runs is quit and the
        /// normal app launched.
        case open(demo: URL?)
        case quit
        case status
    }

    /// How long `open` waits for a launched app to answer, and `quit` for
    /// the app to go, in looks a quarter second apart.
    static let wait: TimeInterval = 10
    static let interval: TimeInterval = 0.25
    /// How long one look at a starting or quitting app waits for an answer:
    /// such an app may accept a connection before (or after) it can answer,
    /// and the looks must fit in `wait`.
    static let lookTimeout: TimeInterval = 1

    static let usageText = """
        usage: video-review app open [--demo <folder>] | quit | status [--json]

          open     launch the app in the background, unless it runs, and wait
                   until it answers (about 10 seconds at most)
                   --demo <folder>: run the app on demo data: a support folder
                   of its own for that folder, leaving yours alone. The window
                   lists the folder's videos. Plain open brings yours back.
          quit     quit the app, and wait until it's gone
          status   whether the app runs: its version, the demo folder, the
                   lease and the open video

        Every command but open exits 1 when the app isn't running.

        """

    /// Reads the arguments after `app`, a demo folder against
    /// `workingDirectory`. `--help` is the usage on standard output;
    /// anything that doesn't read is the usage on standard error, exit 2.
    static func parse(_ arguments: [String], workingDirectory: URL) -> Result<Invocation, CommandResult> {
        if Arguments.asksForHelp(arguments) {
            return .failure(CommandResult(output: usageText))
        }
        guard let subcommand = arguments.first else {
            return .failure(CommandResult(error: usageText, status: CommandResult.usageStatus))
        }
        let rest = Array(arguments.dropFirst())
        switch (subcommand, rest) {
        case ("open", []):
            return .success(.open(demo: nil))
        case ("open", ["--demo"]):
            return .failure(misread("video-review app open: --demo needs a folder"))
        case ("open", let rest) where rest.count == 2 && rest[0] == "--demo":
            return demo(rest[1], workingDirectory: workingDirectory).map { .open(demo: $0) }
        case ("quit", []):
            return .success(.quit)
        case ("status", []):
            return .success(.status)
        case ("open", _), ("quit", _), ("status", _):
            // The first word past the option this subcommand takes, if it led.
            let extra = rest[subcommand == "open" && rest.first == "--demo" ? 2 : 0]
            return .failure(misread("video-review app \(subcommand): unexpected `\(extra)`"))
        default:
            return .failure(misread("video-review app: unknown command `\(subcommand)`"))
        }
    }

    /// The demo folder `path` names, made absolute against the working
    /// folder: it must be a folder.
    private static func demo(_ path: String, workingDirectory: URL) -> Result<URL, CommandResult> {
        let folder = Arguments.absolute(path, in: workingDirectory)
        var isFolder: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isFolder), isFolder.boolValue else {
            return .failure(misread("video-review app open: no folder at \(folder.path)"))
        }
        return .success(folder)
    }

    private static func misread(_ line: String) -> CommandResult {
        .misread(line, usage: usageText)
    }

    static func run(_ arguments: [String], context: CommandContext) -> CommandResult {
        switch parse(arguments, workingDirectory: context.workingDirectory) {
        case .failure(let result):
            return result
        case .success(.status):
            return context.send(.appStatus)
        case .success(.open(nil)):
            return open(context)
        case .success(.open(let demo?)):
            return openDemo(demo, context)
        case .success(.quit):
            switch quit(context.client, context) {
            case .success(let reply): return CommandResult(output: reply.output, error: reply.error)
            case .failure(let result): return result
            }
        }
    }

    /// The normal app's status when it runs. Otherwise it's launched, then
    /// asked for its status every quarter second until it answers, or exit 1
    /// after about 10 seconds. A demo left running is quit first, its
    /// pointer removed, and its lease handed over.
    private static func open(_ context: CommandContext) -> CommandResult {
        let normal = context.client(at: ControlSocket.url(in: context.support))
        var handover: ControlLease.Term?
        if let demo = DemoPointer.recorded(in: context.support) {
            switch quitIfRunning(context.client(at: ControlSocket.url(in: demo.supportFolder)), context) {
            case .success(let lease): handover = lease
            case .failure(let refused): return refused
            }
            do {
                try DemoPointer.remove(in: context.support)
            } catch {
                return .failed("video-review app open: couldn't remove \(DemoPointer.url(in: context.support).path): \(error.localizedDescription)")
            }
        }
        switch normal.send(.appOpen, json: context.json) {
        case .failure(.notRunning):
            return launch(environment: [:], handing: handover, answeringAt: normal, context)
        case let answer:
            // It runs (or is there but failing): no second launch.
            return CommandContext.result(of: answer)
        }
    }

    /// The demo's status when the app already runs on `folder`. Otherwise
    /// the command is pointed at the demo's support folder, whatever app
    /// answers (the normal one, or another demo the pointer named) is quit,
    /// and the app is launched on the demo, with the quit app's lease handed
    /// over, and waited for as `open` does.
    /// The pointer is written before anything is quit, so nothing is quit
    /// when it can't be, and removed again when no demo comes to run.
    private static func openDemo(_ folder: URL, _ context: CommandContext) -> CommandResult {
        let support = DemoPointer.supportFolder(forDemo: folder, in: context.support)
        let socket = ControlSocket.url(in: support)
        guard socket.path.utf8.count <= UnixSocket.maximumPathLength else {
            return .failed("video-review app open: \(UnixSocket.tooLong(socket.path))")
        }
        let pointer = DemoPointer(support: support, folder: folder)
        let demo = context.client(at: socket)
        let previous = DemoPointer.recorded(in: context.support)
        if previous == pointer {
            switch demo.send(.appOpen, json: context.json) {
            case .failure(.notRunning):
                break
            case let answer:
                return CommandContext.result(of: answer)
            }
        }
        do {
            try pointer.record(in: context.support)
        } catch {
            return .failed("video-review app open: couldn't write \(DemoPointer.url(in: context.support).path): \(error.localizedDescription)")
        }
        var sockets = [ControlSocket.url(in: context.support)]
        if let previous, previous != pointer { sockets.append(ControlSocket.url(in: previous.supportFolder)) }
        var outcome: CommandResult?
        var handover: ControlLease.Term?
        for socket in sockets where outcome == nil {
            switch quitIfRunning(context.client(at: socket), context) {
            case .success(let lease): handover = lease ?? handover
            case .failure(let refused): outcome = refused
            }
        }
        let result = outcome ?? launch(
            environment: [AppIdentity.supportVariable: support.path, AppIdentity.demoVariable: folder.path],
            handing: handover,
            answeringAt: demo,
            context
        )
        if result.status != 0 {
            // No demo runs: later commands look for the normal app again.
            try? DemoPointer.remove(in: context.support)
        }
        return result
    }

    /// Quits the app answering `client`, waiting until it's gone: the lease
    /// its reply handed back (nil when nothing ran there), else what to
    /// exit with.
    private static func quitIfRunning(_ client: ControlClient, _ context: CommandContext) -> Result<ControlLease.Term?, CommandResult> {
        if case .failure(.notRunning) = client.send(.appStatus) { return .success(nil) }
        return quit(client, context).map(\.lease)
    }

    /// Launches the app with `environment`, and `handover` handed over in
    /// it, then asks `client` for its status every quarter second until it
    /// answers, or exit 1 after about 10 seconds.
    private static func launch(
        environment: [String: String],
        handing handover: ControlLease.Term?,
        answeringAt client: ControlClient,
        _ context: CommandContext
    ) -> CommandResult {
        let environment = handover.map { environment.merging(ControlLease.handover($0)) { _, lease in lease } } ?? environment
        do throws(AppLaunchFailure) {
            try context.launcher.launch(bundleID: AppIdentity.bundleID, environment: environment)
        } catch {
            return .failed("video-review app open: \(error.reason)")
        }
        // A starting app may accept a connection before it can answer, so
        // each look waits briefly and a slow one is looked at again.
        var look = client
        look.timeout = lookTimeout
        for _ in 0..<looks {
            context.pause(interval)
            switch look.send(.appStatus, json: context.json) {
            case .failure(.notRunning), .failure(.timedOut):
                continue
            case let answer:
                return CommandContext.result(of: answer)
            }
        }
        return .failed("video-review didn't answer within \(Int(wait)) seconds of launching")
    }

    /// Asks the app to quit; once it said it will, waits until nothing
    /// answers on the socket, so a following `app open` launches a new app
    /// instead of finding the old one.
    private static func quit(_ client: ControlClient, _ context: CommandContext) -> Result<ControlReply, CommandResult> {
        let answer = client.send(.appQuit, json: context.json)
        guard case .success(let reply) = answer, reply.ok else { return .failure(CommandContext.result(of: answer)) }
        var look = client
        look.timeout = lookTimeout
        for _ in 0..<looks {
            if case .failure(.notRunning) = look.send(.appStatus) {
                return .success(reply)
            }
            context.pause(interval)
        }
        return .failure(.failed("video-review said it would quit, but it still answers after \(Int(wait)) seconds"))
    }

    private static var looks: Int { Int(wait / interval) }
}
