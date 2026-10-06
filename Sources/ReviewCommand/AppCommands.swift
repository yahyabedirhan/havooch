import Foundation
import ReviewLease
import ReviewWire

/// `havooch app status | open [--demo <folder>] | home | demo | quit`, and
/// `state`. `home` and `demo` are plain requests to the running app.
/// `status` answers without the app; `open` launches it (through
/// `AppLaunching`) when it doesn't run on the data asked for; `quit` waits
/// until it's gone.
enum AppCommands {
    static let commands: [Command] = [
        Command(name: "app status", synopsis: "app status", summary: "whether the app runs, and on which data") {
            arguments, _ throws(UsageError) in
            try arguments.none()
            return .appStatus
        },
        Command(
            name: "app open", synopsis: "app open [--demo <folder>]",
            summary: "start the app; --demo runs it on that folder's data, not yours",
            valuedOptions: ["--demo"]
        ) { arguments, environment throws(UsageError) in
            try arguments.none()
            guard let folder = arguments.options["--demo"] else { return .appOpen(demo: nil) }
            guard !folder.isEmpty else { throw UsageError("`--demo` needs a folder") }
            return .appOpen(demo: URL(fileURLWithPath: folder, isDirectory: true, relativeTo: environment.workingDirectory).standardizedFileURL)
        },
        Command(name: "app home", synopsis: "app home", summary: "go home: close the video and leave the demo, as the Havooch mark does") {
            arguments, _ throws(UsageError) in
            try arguments.none()
            return .send(.appHome)
        },
        Command(name: "app demo", synopsis: "app demo", summary: "run the demo in the same window, as \"Try the Demo\" does") {
            arguments, _ throws(UsageError) in
            try arguments.none()
            return .send(.appDemo)
        },
        Command(name: "app quit", synopsis: "app quit", summary: "quit the app, and wait until it's gone") {
            arguments, _ throws(UsageError) in
            try arguments.none()
            return .appQuit
        },
        Command(name: "state", synopsis: "state", summary: "everything the app shows: the video, the player") {
            arguments, _ throws(UsageError) in
            try arguments.none()
            return .send(.state)
        },
    ]

    /// What running an `app` command needs.
    struct Context {
        /// The normal support folder, where `app open --demo` leaves its
        /// `DemoPointer`.
        var support: URL
        /// The client asking the app at the socket `ControlSocket.locate`
        /// found.
        var client: ControlClient
        var launcher: any AppLaunching
        var pause: @Sendable (TimeInterval) -> Void

        /// The same client, asking at the socket in `support`.
        func client(in support: URL) -> ControlClient {
            var client = client
            client.socket = ControlSocket.url(in: support)
            return client
        }
    }

    /// How long `open` waits for a launched app to answer, and `quit` for
    /// the app to go, in looks a quarter second apart.
    static let wait: TimeInterval = 10
    static let interval: TimeInterval = 0.25
    /// How long one look at a starting or quitting app waits for an answer:
    /// such an app may accept a connection before (or after) it can answer.
    static let lookTimeout: TimeInterval = 1
    private static var looks: Int { Int(wait / interval) }

    // MARK: - status

    /// The app's status, or `not running` (exit 0) when nothing listens.
    static func status(_ context: Context) -> CommandResult {
        let answer = context.client.send(.appStatus)
        guard case .failure(.notRunning) = answer else { return HavoochCLI.result(of: answer) }
        return CommandResult(output: context.client.json ? "{\"running\":false}\n" : "not running\n")
    }

    // MARK: - open

    static func open(demo: URL?, _ context: Context) -> CommandResult {
        if let demo { return openDemo(demo, context) }
        return openNormal(context)
    }

    /// The normal app's status when it runs. Otherwise it's launched and
    /// asked until it answers. A demo left running is quit first and its
    /// pointer removed; the lease its quit renewed is handed to the app
    /// launched.
    private static func openNormal(_ context: Context) -> CommandResult {
        var handover: [String: String] = [:]
        if let demo = DemoPointer.recorded(in: context.support) {
            switch quitIfRunning(context.client(in: demo), context) {
            case .stayed(let refused): return refused
            case .gone(let reply): handover = Self.handover(reply)
            }
            do {
                try DemoPointer.remove(in: context.support)
            } catch {
                return .refused("havooch app open: couldn't remove \(DemoPointer.url(in: context.support).path): \(error.localizedDescription)")
            }
        }
        let normal = context.client(in: context.support)
        switch normal.send(.appOpen) {
        case .failure(.notRunning): return launch(environment: handover, answeringAt: normal, context)
        // It runs (or is there but failing): no second launch.
        case let answer: return HavoochCLI.result(of: answer)
        }
    }

    /// Runs the app on the demo's support folder `demo`, made when it's
    /// missing. A demo already running there just answers. Otherwise the
    /// pointer is written, whatever app answers (the normal one, or another
    /// demo) is quit, and the app is launched on the demo, with the lease
    /// the quit renewed, so the operator keeps it across the relaunch. The
    /// pointer is removed again when no demo comes to run.
    private static func openDemo(_ demo: URL, _ context: Context) -> CommandResult {
        do {
            try FileManager.default.createDirectory(at: demo, withIntermediateDirectories: true)
        } catch {
            return .refused("havooch app open: couldn't make the demo folder \(demo.path): \(error.localizedDescription)")
        }
        let previous = DemoPointer.recorded(in: context.support)
        do {
            try DemoPointer.record(demo, in: context.support)
        } catch {
            return .refused("havooch app open: couldn't write \(DemoPointer.url(in: context.support).path): \(error.localizedDescription)")
        }
        let demoClient = context.client(in: demo)
        switch demoClient.send(.appOpen) {
        case .failure(.notRunning): break
        case let answer: return HavoochCLI.result(of: answer)
        }
        var outcome: CommandResult?
        var environment = [SupportFolder.overrideVariable: demo.path, SupportFolder.demoRunVariable: "1"]
        for other in [context.support, previous].compactMap(\.self) where outcome == nil {
            switch quitIfRunning(context.client(in: other), context) {
            case .stayed(let refused): outcome = refused
            case .gone(let reply): environment.merge(handover(reply)) { _, new in new }
            }
        }
        let result = outcome ?? launch(environment: environment, answeringAt: demoClient, context)
        if result.exitCode != 0 {
            // No demo runs: later commands look for the normal app again.
            try? DemoPointer.remove(in: context.support)
        }
        return result
    }

    /// Launches the app with `environment`, then asks `client` every quarter
    /// second until it answers, or exit 1 after about 10 seconds.
    private static func launch(
        environment: [String: String], answeringAt client: ControlClient, _ context: Context
    ) -> CommandResult {
        do throws(AppLaunchFailure) {
            try context.launcher.launch(environment: environment)
        } catch {
            return .refused("havooch app open: \(error.reason)")
        }
        // A starting app may accept a connection before it can answer, so
        // each look waits briefly and a slow one is looked at again.
        var look = client
        look.timeout = lookTimeout
        for _ in 0..<looks {
            context.pause(interval)
            switch look.send(.appOpen) {
            case .failure(.notRunning), .failure(.timedOut): continue
            case let answer: return HavoochCLI.result(of: answer)
            }
        }
        return .refused("\(AppIdentity.appName) didn't answer within \(Int(wait)) seconds of launching")
    }

    // MARK: - quit

    static func quit(_ context: Context) -> CommandResult {
        switch quitAndWait(context.client, context) {
        case .gone(let reply): CommandResult(output: reply?.output ?? "", error: reply?.error ?? "")
        case .stayed(let result): result
        }
    }

    /// How a quit went: the app is gone, with its last reply (none when it
    /// never ran), or what to exit with.
    private enum Quit {
        case gone(ControlReply?)
        case stayed(CommandResult)
    }

    /// What a relaunch adds to the launched app's environment: the lease
    /// the quit's `reply` carries, when it carries one.
    private static func handover(_ reply: ControlReply?) -> [String: String] {
        reply?.lease.map(ControlLease.handover) ?? [:]
    }

    /// Quits the app answering `client` and waits until it's gone. An app
    /// that never ran is gone, with no reply.
    private static func quitIfRunning(_ client: ControlClient, _ context: Context) -> Quit {
        if case .failure(.notRunning) = client.send(.appStatus) { return .gone(nil) }
        return quitAndWait(client, context)
    }

    /// Asks the app to quit; once it said it will, waits until nothing
    /// answers on the socket, so a following `app open` launches a new app
    /// instead of finding the old one.
    private static func quitAndWait(_ client: ControlClient, _ context: Context) -> Quit {
        let answer = client.send(.appQuit)
        guard case .success(let reply) = answer, reply.ok else { return .stayed(HavoochCLI.result(of: answer)) }
        var look = client
        look.timeout = lookTimeout
        for _ in 0..<looks {
            if case .failure(.notRunning) = look.send(.appStatus) { return .gone(reply) }
            context.pause(interval)
        }
        return .stayed(.refused("\(AppIdentity.appName) said it would quit, but it still answers after \(Int(wait)) seconds"))
    }
}
