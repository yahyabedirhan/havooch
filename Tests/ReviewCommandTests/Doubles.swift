import Foundation
import ReviewCommand
import ReviewWire

/// The app, in memory: answers each message with `answer`, by the socket it
/// was sent to, and records every one.
final class FakeTransport: ControlTransport, @unchecked Sendable {
    typealias Answer = (ControlMessage, URL) -> Result<ControlReply, ControlTransportFailure>

    var answer: Answer
    private(set) var sent: [(message: ControlMessage, socket: URL)] = []

    init(_ answer: @escaping Answer = { _, _ in .failure(.notRunning) }) {
        self.answer = answer
    }

    var requests: [ControlRequest] { sent.map(\.message.request) }

    func exchange(_ request: Data, socket: URL, timeout: TimeInterval?) throws(ControlTransportFailure) -> Data {
        guard let message = try? ControlMessage.decode(request) else { throw .failed("the test sent an unreadable request") }
        sent.append((message, socket))
        switch answer(message, socket) {
        case .success(let reply): return reply.encoded()
        case .failure(let failure): throw failure
        }
    }
}

/// Records each launch, and runs `launched` so a test can start its fake app.
final class FakeLauncher: AppLaunching, @unchecked Sendable {
    private(set) var launches: [[String: String]] = []
    var failure: AppLaunchFailure?
    var launched: ([String: String]) -> Void = { _ in }

    func launch(environment: [String: String]) throws(AppLaunchFailure) {
        if let failure { throw failure }
        launches.append(environment)
        launched(environment)
    }
}

struct NoProcesses: ProcessTable {
    var currentPID: Int32 { 1 }
    func process(_ pid: Int32) -> ProcessRecord? { nil }
}

/// A command run in a temporary support folder, removed with `cleanUp()`.
struct Run {
    let folder: URL
    let support: URL
    let transport: FakeTransport
    let launcher = FakeLauncher()

    init(_ answer: @escaping FakeTransport.Answer = { _, _ in .failure(.notRunning) }) {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("video-review-tests-\(UUID().uuidString)", isDirectory: true)
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
        VideoReviewCLI.run(arguments, environment: environment)
    }
}
