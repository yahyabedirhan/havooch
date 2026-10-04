import Foundation
import VRCommand
import VRLease
import VRWire

/// A value several threads read and change, behind a lock.
final class Locked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) {
        self.value = value
    }

    func withValue<T>(_ change: (inout Value) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return change(&value)
    }

    var current: Value { withValue { $0 } }
}

/// The app's end of the socket, in memory: each exchange is recorded, with
/// the socket and timeout it was sent with, and answered by `answer`.
final class FakeTransport: ControlTransport {
    struct Exchange: Equatable {
        var message: ControlMessage
        var socket: String
        var idleTimeout: TimeInterval
    }

    let exchanges = Locked<[Exchange]>([])
    private let answer: @Sendable (ControlMessage, String) -> Result<ControlReply, ControlTransportFailure>

    /// `answer` gets each message and the file name of the socket it was
    /// sent to (`control.sock`, `demo.sock`).
    init(answer: @escaping @Sendable (_ message: ControlMessage, _ socket: String) -> Result<ControlReply, ControlTransportFailure>) {
        self.answer = answer
    }

    /// An app that answers every request with `reply`.
    convenience init(reply: ControlReply) {
        self.init { _, _ in .success(reply) }
    }

    /// No app: nothing listens.
    static var nothingListens: FakeTransport { FakeTransport { _, _ in .failure(.notRunning) } }

    func exchange(_ request: Data, socket: URL, idleTimeout: TimeInterval) throws(ControlTransportFailure) -> Data {
        // A request the CLI sent always reads; a test that fails here broke the encoding.
        let message = try! ControlMessage.decode(request)
        exchanges.withValue { $0.append(Exchange(message: message, socket: socket.lastPathComponent, idleTimeout: idleTimeout)) }
        return try answer(message, socket.lastPathComponent).get().encoded()
    }

    /// The requests sent, in order.
    var requests: [ControlRequest] { exchanges.current.map(\.message.request) }
    /// The requests sent with the socket each went to.
    var sent: [String] { exchanges.current.map { "\($0.message.request.command) @ \($0.socket)" } }
}

/// A process table in memory: the `video-review` command is `currentPID`,
/// and `processes` its ancestors.
struct FakeProcessTable: ProcessTable {
    var currentPID: Int32
    var processes: [ProcessRecord]

    func process(_ pid: Int32) -> ProcessRecord? {
        processes.first { $0.pid == pid }
    }

    /// The tree the command tests run in: `video-review` (500), run by
    /// `zsh` (400) under the agent `claude` (300), under `launchd` (1).
    static let agent = FakeProcessTable(currentPID: 500, processes: [
        ProcessRecord(pid: 500, parent: 400, started: Date(timeIntervalSince1970: 1_000), name: "video-review"),
        ProcessRecord(pid: 400, parent: 300, started: Date(timeIntervalSince1970: 900), name: "zsh"),
        ProcessRecord(pid: 300, parent: 1, started: Date(timeIntervalSince1970: 800.25), name: "claude"),
        ProcessRecord(pid: 1, parent: 0, started: Date(timeIntervalSince1970: 0), name: "launchd"),
    ])
}

/// A launcher that records each launch and fails with `failure` when set.
final class RecordingLauncher: AppLaunching {
    struct Launch: Equatable {
        var bundle: URL?
        var environment: [String: String]
    }

    let launches = Locked<[Launch]>([])
    let failure: AppLaunchFailure?

    init(failure: AppLaunchFailure? = nil) {
        self.failure = failure
    }

    func launch(bundle: URL?, environment: [String: String]) throws(AppLaunchFailure) {
        launches.withValue { $0.append(Launch(bundle: bundle, environment: environment)) }
        if let failure { throw failure }
    }
}

/// A command line run against fakes, in a support folder of its own that
/// is removed when the test ends.
final class CommandHarness {
    let support = FileManager.default.temporaryDirectory.appendingPathComponent("vr-command-\(UUID().uuidString)", isDirectory: true)
    let work = URL(fileURLWithPath: "/work", isDirectory: true)
    let bundle = URL(fileURLWithPath: "/Applications/Video Review (test).app", isDirectory: true)
    let launcher: RecordingLauncher
    let pauses = Locked<Int>(0)

    init(launcher: RecordingLauncher = RecordingLauncher()) {
        self.launcher = launcher
    }

    deinit { try? FileManager.default.removeItem(at: support) }

    func run(_ line: String..., variables: [String: String] = [:], transport: FakeTransport) -> CommandResult {
        run(line: line, variables: variables, transport: transport)
    }

    func run(line: [String], variables: [String: String] = [:], transport: FakeTransport) -> CommandResult {
        let pauses = pauses
        return CLI.run(arguments: line, environment: CommandEnvironment(
            variables: variables, workingDirectory: work, processes: FakeProcessTable.agent,
            transport: transport, launcher: launcher, bundle: bundle, support: support,
            pause: { _ in pauses.withValue { $0 += 1 } }
        ))
    }
}
