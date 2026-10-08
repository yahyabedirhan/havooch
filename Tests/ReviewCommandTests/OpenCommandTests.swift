import Foundation
import ReviewCommand
import ReviewLease
import ReviewWire
import Synchronization
import Testing

@Suite("havooch open")
struct OpenCommandTests {
    static let opened = "opened cut2.mp4 (0:21.233), playing\n"
    /// The fake app's process, which its reply to `open` names.
    static let pid: Int32 = 4242

    /// A run with a video file at `cut2.mp4` in its folder, against an app
    /// that answers once `running` is true. A launch starts it.
    private func makeRun(running: Bool) throws -> (run: Run, video: URL) {
        let state = Running(running)
        let run = Run { message, _ in
            guard state.value.withLock({ $0 }) else { return .failure(.notRunning) }
            switch message.request {
            case .open: return .success(ControlReply(ok: true, output: Self.opened, pid: Self.pid))
            default: return .success(.done("running\n"))
            }
        }
        try FileManager.default.createDirectory(at: run.folder, withIntermediateDirectories: true)
        let video = run.folder.appendingPathComponent("cut2.mp4")
        try Data("not really a video".utf8).write(to: video)
        run.launcher.launched = { _ in state.value.withLock { $0 = true } }
        return (run, video)
    }

    /// Whether the fake app runs.
    private final class Running: Sendable {
        let value: Mutex<Bool>

        init(_ running: Bool) {
            value = Mutex(running)
        }
    }

    @Test("on a running app it asks the app to open the absolute path, brings its process to the front, launches nothing, and takes no lease")
    func running() throws {
        let (run, video) = try makeRun(running: true)
        defer { run.cleanUp() }
        #expect(run("open", video.path) == CommandResult(output: Self.opened))
        #expect(run.launcher.fronted == [Self.pid])
        #expect(run.launcher.launches.isEmpty)
        #expect(run.transport.requests == [.open(path: video.path)])
        #expect(ControlRequest.open(path: video.path).role == .person)
    }

    @Test("an app that can't be brought to the front still opened the video: exit 0, with a note on standard error")
    func notInFront() throws {
        let (run, video) = try makeRun(running: true)
        defer { run.cleanUp() }
        run.launcher.frontWorks = false
        #expect(run("open", video.path)
            == CommandResult(output: Self.opened, error: "\(AppIdentity.appName) couldn't be brought to the front\n"))
    }

    @Test("a relative path is made absolute against the folder the command runs in")
    func relative() throws {
        let (run, video) = try makeRun(running: true)
        defer { run.cleanUp() }
        var environment = run.environment
        environment.workingDirectory = run.folder
        let result = HavoochCLI.run(["open", "./sub/../cut2.mp4"], environment: environment)
        #expect(result == CommandResult(output: Self.opened))
        #expect(run.transport.requests == [.open(path: video.standardizedFileURL.path)])
    }

    @Test("when the app doesn't run it's launched in front, with no environment, and asked to open once it answers")
    func launches() throws {
        let (run, video) = try makeRun(running: false)
        defer { run.cleanUp() }
        #expect(run("open", video.path) == CommandResult(output: Self.opened))
        #expect(run.launcher.launches == [[:]])
        #expect(run.launcher.inFront == [true])
        #expect(run.launcher.fronted == [Self.pid])
        // The open is asked for once, after the app answered a status.
        #expect(run.transport.requests == [.open(path: video.path), .appStatus, .open(path: video.path)])
    }

    @Test("a launch that fails is refused with the reason, exit 1")
    func launchFails() throws {
        let (run, video) = try makeRun(running: false)
        defer { run.cleanUp() }
        run.launcher.failure = AppLaunchFailure("Havooch isn't installed")
        #expect(run("open", video.path) == CommandResult(error: "havooch open: Havooch isn't installed\n", exitCode: 1))
    }

    @Test("a launched app that never answers is refused after 10 seconds, without asking it to open")
    func neverAnswers() throws {
        let (run, video) = try makeRun(running: false)
        defer { run.cleanUp() }
        run.launcher.launched = { _ in }
        #expect(run("open", video.path)
            == CommandResult(error: "\(AppIdentity.appName) didn't answer within 10 seconds of launching\n", exitCode: 1))
        #expect(run.transport.requests.filter { $0 == .open(path: video.path) }.count == 1)
    }

    @Test("a path with no file, or a folder, is refused before the app is asked or launched")
    func noFile() throws {
        let (run, video) = try makeRun(running: false)
        defer { run.cleanUp() }
        let missing = run.folder.appendingPathComponent("missing.mp4").path
        #expect(run("open", missing) == CommandResult(error: "havooch open: no video file at \(missing)\n", exitCode: 1))
        #expect(run("open", run.folder.path) == CommandResult(error: "havooch open: no video file at \(run.folder.path)\n", exitCode: 1))
        #expect(run.transport.requests.isEmpty)
        #expect(run.launcher.launches.isEmpty)
        _ = video
    }

    @Test("a file the app can't play is the app's refusal, exit 1")
    func unplayable() throws {
        let (run, video) = try makeRun(running: true)
        defer { run.cleanUp() }
        let line = "can't play \(video.path): it has no video this Mac can play"
        run.transport.answer = { _, _ in .success(.refused(line)) }
        #expect(run("open", video.path) == CommandResult(error: line + "\n", exitCode: 1))
    }

    @Test("open needs its path, and only one")
    func usage() throws {
        let (run, _) = try makeRun(running: true)
        defer { run.cleanUp() }
        #expect(run("open").exitCode == CommandResult.usageCode)
        #expect(run("open", "a.mp4", "b.mp4").exitCode == CommandResult.usageCode)
        #expect(run.transport.requests.isEmpty)
    }
}
