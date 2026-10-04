import Foundation
import VRLease
import VRWire

/// `video-review app status | open | quit`: the commands with steps of
/// their own, since the app may not be running, or may run on other data
/// than the command wants.
struct AppCommand {
    /// The real support folder: the sockets and the demo pointer.
    var support: URL
    /// A client for this command's holder; its socket is set per request.
    var client: ControlClient
    var launcher: any AppLaunching
    /// The app bundle the command sits in, which `open` starts.
    var bundle: URL?
    /// Waits between two looks at the app while it starts or quits.
    var pause: @Sendable (TimeInterval) -> Void
    var json: Bool

    /// How long `open` waits for a launched app to answer, and `quit` for
    /// the app to go, in looks a quarter second apart.
    static let wait: TimeInterval = 10
    static let interval: TimeInterval = 0.25
    /// How long one look at a starting or quitting app waits for an
    /// answer: such an app may accept a connection before (or after) it
    /// can answer, and the looks must fit in `wait`.
    static let lookTimeout: TimeInterval = 1

    static let notRunning = "video-review isn't running; `video-review app open`"

    /// The data an app runs on.
    private enum RunningData: Equatable {
        case real
        /// The demo folder's path, or nil when no pointer says which.
        case demo(String?)
    }

    // MARK: - status

    /// The app's status; `not running`, exit 0, when nothing answers.
    func status() -> CommandResult {
        let answer = client(at: ControlSocket.locate(support: support)).send(.appStatus, json: json)
        if case .failure(.notRunning) = answer {
            return CommandResult(output: json ? "{\"running\":false}\n" : "not running\n")
        }
        return Self.result(of: answer)
    }

    // MARK: - open

    /// Starts the app on `wanted` (a demo folder, or nil for the person's
    /// data) and prints its status. An app that already runs on that data
    /// is only asked, which renews the lease. One on other data is quit
    /// first, and its lease handed over to the app launched. The demo
    /// pointer is written before a demo is launched and removed again when
    /// none comes to run.
    func open(demo wanted: URL?) -> CommandResult {
        var handover: ControlLease.Term?
        if let (socket, data) = running() {
            if data == (wanted.map { .demo($0.standardizedFileURL.path) } ?? .real) {
                return Self.result(of: client(at: socket).send(.appOpen, json: json))
            }
            switch quit(at: socket) {
            case .success(let reply): handover = reply.lease
            case .failure(let refused): return refused
            }
        }
        do {
            if let wanted {
                try FileManager.default.createDirectory(at: wanted, withIntermediateDirectories: true)
                try DemoPointer.record(wanted, in: support)
            } else {
                try DemoPointer.remove(in: support)
            }
        } catch {
            return .failed("video-review app open: couldn't set up \(wanted?.path ?? DemoPointer.url(in: support).path): \(error.localizedDescription)")
        }
        let outcome = launch(demo: wanted, handing: handover)
        if outcome.exitCode != CommandResult.success, wanted != nil {
            // No demo runs: later commands look for the person's app again.
            try? DemoPointer.remove(in: support)
        }
        return outcome
    }

    /// The app that answers, if any: its socket and the data it runs on.
    /// Both sockets are asked, the demo's first, so an app is found even
    /// when the pointer is stale. An app that's there but failing counts.
    private func running() -> (socket: URL, data: RunningData)? {
        let pointer = DemoPointer.recorded(in: support).map(\.standardizedFileURL.path)
        let candidates: [(URL, RunningData)] = [
            (ControlSocket.demo(in: support), .demo(pointer)),
            (ControlSocket.real(in: support), .real),
        ]
        for (socket, data) in candidates {
            var look = client(at: socket)
            look.idleTimeout = Self.lookTimeout
            if case .failure(.notRunning) = look.send(.appStatus) { continue }
            return (socket, data)
        }
        return nil
    }

    /// Launches the app on `demo`, with `handover` handed over when there's
    /// one, then asks it to open every quarter second until it answers, or
    /// exit 1 after about 10 seconds.
    private func launch(demo: URL?, handing handover: ControlLease.Term?) -> CommandResult {
        var environment: [String: String] = [:]
        if let demo { environment[SupportFolder.overrideVariable] = demo.path }
        if let handover { environment.merge(ControlLease.handover(handover)) { _, lease in lease } }
        do throws(AppLaunchFailure) {
            try launcher.launch(bundle: bundle, environment: environment)
        } catch {
            return .failed("video-review app open: \(error.reason)")
        }
        var look = client(at: demo == nil ? ControlSocket.real(in: support) : ControlSocket.demo(in: support))
        look.idleTimeout = Self.lookTimeout
        for _ in 0..<Self.looks {
            pause(Self.interval)
            switch look.send(.appOpen, json: json) {
            case .failure(.notRunning), .failure(.timedOut):
                continue
            case let answer:
                return Self.result(of: answer)
            }
        }
        return .failed("video-review didn't answer within \(Int(Self.wait)) seconds of launching")
    }

    // MARK: - quit

    /// Quits the app that answers on the located socket, and waits until
    /// it's gone.
    func quit() -> CommandResult {
        switch quit(at: ControlSocket.locate(support: support)) {
        case .success(let reply): CommandResult(output: reply.output, error: reply.error)
        case .failure(let result): result
        }
    }

    /// Asks the app at `socket` to quit; once it said it will, waits until
    /// nothing answers there, so a following `app open` launches a new app
    /// instead of finding the old one. The quit's reply, with the lease it
    /// renewed, else what to exit with.
    private func quit(at socket: URL) -> Result<ControlReply, CommandResult> {
        let answer = client(at: socket).send(.appQuit, json: json)
        guard case .success(let reply) = answer, reply.ok else { return .failure(Self.result(of: answer)) }
        var look = client(at: socket)
        look.idleTimeout = Self.lookTimeout
        for _ in 0..<Self.looks {
            if case .failure(.notRunning) = look.send(.appStatus) { return .success(reply) }
            pause(Self.interval)
        }
        return .failure(.failed("video-review said it would quit, but it still answers after \(Int(Self.wait)) seconds"))
    }

    // MARK: - shared

    private static var looks: Int { Int(wait / interval) }

    /// The same client, asking at `socket`.
    func client(at socket: URL) -> ControlClient {
        var client = client
        client.socket = socket
        return client
    }

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
