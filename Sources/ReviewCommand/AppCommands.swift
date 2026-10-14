import Foundation
import ReviewLease
import ReviewWire

enum AppCommands {
    static let group = CommandGroup(
        name: "app", summary: "start, quit and check the app", section: .drive, commands: [
            Command(
                name: "app status", summary: "print whether the app runs, and on which data",
                description: "It answers `not running` without the app.", examples: ["", "--json"], role: .free
            ) { arguments, _ throws(UsageError) in
                try arguments.none()
                return .appStatus
            },
            Command(
                name: "app open", arguments: "[--demo <folder>]", summary: "start the app",
                description: "With --demo, the app runs on that folder's data, not yours, and a demo or the normal app that "
                    + "runs is quit first. A running app on the data asked for just answers.",
                examples: ["", "--demo /tmp/havooch-demo"], role: .operator, valuedOptions: ["--demo"]
            ) { arguments, environment throws(UsageError) in
                try arguments.none()
                guard let folder = arguments.options["--demo"] else { return .appOpen(demo: nil) }
                guard !folder.isEmpty else { throw UsageError("`--demo` needs a folder") }
                return .appOpen(demo: URL(fileURLWithPath: folder, isDirectory: true, relativeTo: environment.workingDirectory).standardizedFileURL)
            },
            Command(
                name: "app home", summary: "go home: close the video and leave the demo",
                description: "As a click on the Havooch mark in the header does.", examples: ["", "--window w2"], role: .operator
            ) { arguments, _ throws(UsageError) in
                try arguments.none()
                return .send(.appHome)
            }.onAWindow(),
            Command(
                name: "app demo", summary: "run the demo in the window",
                description: "As \"Try the Demo\" does.", examples: ["", "--window w2"], role: .operator
            ) { arguments, _ throws(UsageError) in
                try arguments.none()
                return .send(.appDemo)
            }.onAWindow(),
            Command(
                name: "app quit", summary: "quit the app and wait until it's gone",
                examples: [""], role: .operator
            ) { arguments, _ throws(UsageError) in
                try arguments.none()
                return .appQuit
            },
        ]
    )

    struct Context {
        var support: URL
        var client: ControlClient
        var launcher: any AppLaunching
        var pause: @Sendable (TimeInterval) -> Void
        var muted = false

        func client(in support: URL) -> ControlClient {
            var client = client
            client.socket = ControlSocket.url(in: support)
            return client
        }
    }

    static let wait: TimeInterval = 10
    static let interval: TimeInterval = 0.25
    static let lookTimeout: TimeInterval = 1
    private static var looks: Int { Int(wait / interval) }

    static func status(_ context: Context) -> CommandResult {
        let answer = context.client.send(.appStatus)
        guard case .failure(.notRunning) = answer else { return HavoochCLI.result(of: answer) }
        return CommandResult(output: context.client.json ? "{\"running\":false}\n" : "not running\n")
    }

    static func open(demo: URL?, _ context: Context) -> CommandResult {
        if let demo { return openDemo(demo, context) }
        return openNormal(context)
    }

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
        case let answer: return HavoochCLI.result(of: answer)
        }
    }

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
        if context.muted { environment[MutedRun.variable] = "1" }
        for other in [context.support, previous].compactMap(\.self) where outcome == nil {
            switch quitIfRunning(context.client(in: other), context) {
            case .stayed(let refused): outcome = refused
            case .gone(let reply): environment.merge(handover(reply)) { _, new in new }
            }
        }
        let result = outcome ?? launch(environment: environment, answeringAt: demoClient, context)
        if result.exitCode != 0 {
            try? DemoPointer.remove(in: context.support)
        }
        return result
    }

    private static func launch(
        environment: [String: String], answeringAt client: ControlClient, _ context: Context
    ) -> CommandResult {
        do throws(AppLaunchFailure) {
            try context.launcher.launch(environment: environment)
        } catch {
            return .refused("havooch app open: \(error.reason)")
        }
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

    static func quit(_ context: Context) -> CommandResult {
        switch quitAndWait(context.client, context) {
        case .gone(let reply): CommandResult(output: reply?.output ?? "", error: reply?.error ?? "")
        case .stayed(let result): result
        }
    }

    private enum Quit {
        case gone(ControlReply?)
        case stayed(CommandResult)
    }

    private static func handover(_ reply: ControlReply?) -> [String: String] {
        reply?.lease.map(ControlLease.handover) ?? [:]
    }

    private static func quitIfRunning(_ client: ControlClient, _ context: Context) -> Quit {
        if case .failure(.notRunning) = client.send(.appStatus) { return .gone(nil) }
        return quitAndWait(client, context)
    }

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
