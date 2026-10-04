import Foundation
import VRCommand
import VRLease
import VRWire

/// The app as the command sees it, in memory: which sockets something
/// answers on, every request sent and every launch asked for. A socket that
/// answers also exists as a file, since the command looks for the demo's.
final class FakeApp: ControlTransport, AppLaunching, @unchecked Sendable {
    /// The normal support folder, a temporary one.
    let support: URL
    private let lock = NSLock()
    private var running: Set<String> = []
    private var sent: [(request: ControlRequest, json: Bool, socket: URL)] = []
    private var launched: [(bundleID: String, environment: [String: String])] = []
    private var waited: [TimeInterval] = []
    /// Set to make every exchange run out of time instead of answering.
    var timesOut = false
    /// What the app answers each request with; `done` with the command's
    /// wire name by default.
    var answer: @Sendable (ControlMessage) -> ControlReply = { .done("\($0.request)\n") }
    /// Set to make the next launch fail.
    var launchFailure: AppLaunchFailure?

    init() throws {
        support = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("vr-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: support)
    }

    var requests: [ControlRequest] { lock.withLock { sent.map(\.request) } }
    var messages: [(request: ControlRequest, json: Bool, socket: URL)] { lock.withLock { sent } }
    var launches: [(bundleID: String, environment: [String: String])] { lock.withLock { launched } }
    /// How long each exchange was given to answer, in the order sent.
    var timeouts: [TimeInterval] { lock.withLock { waited } }

    /// The environment a command runs with: this fake as the socket and as
    /// Launch Services, and the temporary support folder.
    var environment: CommandEnvironment {
        CommandEnvironment(
            variables: [AppIdentity.supportVariable: support.path, "CLAUDE_CODE_SESSION_ID": "test"],
            workingDirectory: URL(fileURLWithPath: "/Users/me/repo", isDirectory: true),
            transport: self,
            launcher: self,
            processes: SystemProcessTable(),
            pause: { _ in }
        )
    }

    /// Makes an app answer on the socket in `folder`.
    func start(in folder: URL) {
        let socket = ControlSocket.url(in: folder)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? Data().write(to: socket)
        lock.withLock { _ = running.insert(socket.path) }
    }

    func isRunning(in folder: URL) -> Bool {
        lock.withLock { running.contains(ControlSocket.url(in: folder).path) }
    }

    func exchange(_ request: Data, socket: URL, timeout: TimeInterval) throws(ControlTransportFailure) -> Data {
        guard lock.withLock({ running.contains(socket.path) }) else { throw .notRunning }
        guard let message = try? ControlMessage.decode(request) else { throw .failed("the fake app couldn't read the request") }
        lock.withLock {
            sent.append((message.request, message.json, socket))
            waited.append(timeout)
        }
        if timesOut { throw .timedOut }
        if message.request == .appQuit {
            lock.withLock { _ = running.remove(socket.path) }
            try? FileManager.default.removeItem(at: socket)
        }
        return answer(message).encoded()
    }

    func launch(bundleID: String, environment: [String: String]) throws(AppLaunchFailure) {
        if let launchFailure { throw launchFailure }
        lock.withLock { launched.append((bundleID, environment)) }
        start(in: environment[AppIdentity.supportVariable].map { URL(fileURLWithPath: $0, isDirectory: true) } ?? support)
    }
}
