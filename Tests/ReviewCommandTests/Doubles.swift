import Foundation
import ReviewCommand
import ReviewLease
import ReviewWire
import Synchronization

/// The app, in memory: answers each message with `answer`, by the socket it
/// was sent to, and records every one.
final class FakeTransport: ControlTransport {
    typealias Answer = @Sendable (ControlMessage, URL) -> Result<ControlReply, ControlTransportFailure>

    private struct State {
        var answer: Answer
        var sent: [(message: ControlMessage, socket: URL)] = []
    }

    private let state: Mutex<State>

    init(_ answer: @escaping Answer = { _, _ in .failure(.notRunning) }) {
        state = Mutex(State(answer: answer))
    }

    var answer: Answer {
        get { state.withLock { $0.answer } }
        set { state.withLock { $0.answer = newValue } }
    }

    var sent: [(message: ControlMessage, socket: URL)] { state.withLock { $0.sent } }

    var requests: [ControlRequest] { sent.map(\.message.request) }

    func exchange(_ request: Data, socket: URL, timeout: TimeInterval?) throws(ControlTransportFailure) -> Data {
        guard let message = try? ControlMessage.decode(request) else { throw .failed("the test sent an unreadable request") }
        let answer: Answer = state.withLock {
            $0.sent.append((message, socket))
            return $0.answer
        }
        // Answered outside the lock: an answer may read the test's other doubles.
        switch answer(message, socket) {
        case .success(let reply): return reply.encoded()
        case .failure(let failure): throw failure
        }
    }
}

/// Records each launch, and runs `launched` so a test can start its fake app.
final class FakeLauncher: AppLaunching {
    private struct State {
        var launches: [[String: String]] = []
        var inFront: [Bool] = []
        var fronted: [Int32] = []
        var frontWorks = true
        var failure: AppLaunchFailure?
        var launched: @Sendable ([String: String]) -> Void = { _ in }
    }

    private let state = Mutex(State())

    var launches: [[String: String]] { state.withLock { $0.launches } }

    var failure: AppLaunchFailure? {
        get { state.withLock { $0.failure } }
        set { state.withLock { $0.failure = newValue } }
    }

    var launched: @Sendable ([String: String]) -> Void {
        get { state.withLock { $0.launched } }
        set { state.withLock { $0.launched = newValue } }
    }

    /// The processes brought to the front, in order.
    var fronted: [Int32] { state.withLock { $0.fronted } }

    /// Whether bringing a process to the front works.
    var frontWorks: Bool {
        get { state.withLock { $0.frontWorks } }
        set { state.withLock { $0.frontWorks = newValue } }
    }

    func bringToFront(pid: Int32) -> Bool {
        state.withLock {
            $0.fronted.append(pid)
            return $0.frontWorks
        }
    }

    /// Whether each launch asked for the app in front, in order.
    var inFront: [Bool] { state.withLock { $0.inFront } }

    func launch(environment: [String: String], inFront: Bool) throws(AppLaunchFailure) {
        if let failure { throw failure }
        let launched: @Sendable ([String: String]) -> Void = state.withLock {
            $0.launches.append(environment)
            $0.inFront.append(inFront)
            return $0.launched
        }
        launched(environment)
    }
}

struct NoProcesses: ProcessTable {
    var currentPID: Int32 { 1 }
    func process(_ pid: Int32) -> ProcessRecord? { nil }
}

/// A command run in a temporary support folder, removed with `cleanUp`.
struct Run {
    let folder: URL
    let support: URL
    let transport: FakeTransport
    let launcher = FakeLauncher()

    init(_ answer: @escaping FakeTransport.Answer = { _, _ in .failure(.notRunning) }) {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("havooch-tests-\(UUID().uuidString)", isDirectory: true)
        support = folder.appendingPathComponent("support", isDirectory: true)
        transport = FakeTransport(answer)
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: folder)
    }

    var environment: CommandEnvironment {
        CommandEnvironment(
            variables: [SupportFolder.overrideVariable: support.path, "CLAUDE_CODE_SESSION_ID": "abc"],
            workingDirectory: URL(fileURLWithPath: "/Users/me/shop", isDirectory: true),
            processes: NoProcesses(),
            transport: transport,
            launcher: launcher,
            pause: { _ in }
        )
    }

    func callAsFunction(_ arguments: String...) -> CommandResult {
        HavoochCLI.run(arguments, environment: environment)
    }
}
