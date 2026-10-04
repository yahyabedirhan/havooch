import Foundation
import ReviewCommand
import ReviewWire
import Testing

@Suite("The video-review command")
struct CommandTests {
    @Test("each command sends its request", arguments: [
        (["state"], ControlRequest.state),
        (["player", "open", "/videos/sample.mp4"], .playerOpen(path: "/videos/sample.mp4")),
        (["player", "open", "clips/../sample.mp4"], .playerOpen(path: "/Users/me/shop/sample.mp4")),
        (["player", "play"], .playerPlay),
        (["player", "pause"], .playerPause),
        (["player", "seek", "0:10"], .playerSeek(seconds: 10)),
        (["player", "seek", "12.5"], .playerSeek(seconds: 12.5)),
        (["screenshot", "/tmp/shot.png"], .screenshot(path: "/tmp/shot.png", appearance: nil)),
        (["screenshot", "/tmp/shot.png", "--appearance", "dark"], .screenshot(path: "/tmp/shot.png", appearance: .dark)),
        (["screenshot", "--appearance", "light", "/tmp/shot.png"], .screenshot(path: "/tmp/shot.png", appearance: .light)),
    ])
    func sends(arguments: [String], request: ControlRequest) {
        let run = Run { _, _ in .success(.done("done\n")) }
        defer { run.cleanUp() }
        let result = VideoReviewCLI.run(arguments, environment: run.environment)
        #expect(result == CommandResult(output: "done\n"))
        #expect(run.transport.requests == [request])
    }

    @Test("a request carries the holder, and --json wherever it's written")
    func holderAndJSON() {
        let run = Run { _, _ in .success(.done("{}\n")) }
        defer { run.cleanUp() }
        _ = run("player", "seek", "0:10")
        _ = run("--json", "player", "seek", "0:10")
        _ = run("state", "--json")
        #expect(run.transport.sent.map(\.message.json) == [false, true, true])
        #expect(run.transport.sent[0].message.holder == Holder(key: "CLAUDE_CODE_SESSION_ID=abc", name: "Claude Code", place: "/Users/me/shop"))
        #expect(run.transport.sent[0].socket == ControlSocket.url(in: run.support))
    }

    @Test("a refusal is one line on standard error, exit 1")
    func refused() {
        let run = Run { _, _ in .success(.refused("0:40 is outside the video (0:00 to 0:21.233)")) }
        defer { run.cleanUp() }
        #expect(run("player", "seek", "0:40") == CommandResult(error: "0:40 is outside the video (0:00 to 0:21.233)\n", exitCode: 1))
    }

    @Test("every command but app status and app open exits 1 when the app isn't running")
    func notRunning() {
        let run = Run()
        defer { run.cleanUp() }
        let line = "\(AppIdentity.appName) isn't running; run `video-review app open`\n"
        #expect(run("player", "play") == CommandResult(error: line, exitCode: 1))
        #expect(run("state", "--json") == CommandResult(error: line, exitCode: 1))
        #expect(run("app", "quit") == CommandResult(error: line, exitCode: 1))
        #expect(run("app", "status") == CommandResult(output: "not running\n"))
        #expect(run("app", "status", "--json") == CommandResult(output: "{\"running\":false}\n"))
    }

    @Test("arguments that don't read exit 64 and send nothing", arguments: [
        [], ["rewind"], ["player"], ["player", "rewind"], ["player", "seek"], ["player", "seek", "soon"],
        ["player", "seek", "-5"], ["player", "seek", "1", "2"], ["player", "open"], ["player", "play", "now"],
        ["screenshot"], ["screenshot", "shot.png"], ["screenshot", "/tmp/shot.jpg"],
        ["screenshot", "/tmp/shot.png", "--appearance", "sepia"], ["screenshot", "/tmp/shot.png", "--appearance"],
        ["state", "--verbose"], ["app", "open", "--demo"], ["app", "status", "now"],
    ])
    func usage(arguments: [String]) {
        let run = Run { _, _ in .success(.done("done\n")) }
        defer { run.cleanUp() }
        let result = VideoReviewCLI.run(arguments, environment: run.environment)
        #expect(result.exitCode == 64)
        #expect(result.output.isEmpty)
        #expect(result.error.contains("usage: video-review"))
        #expect(run.transport.sent.isEmpty)
        #expect(run.launcher.launches.isEmpty)
    }

    @Test("--help prints the usage on standard output")
    func help() {
        let run = Run()
        defer { run.cleanUp() }
        let result = run("--help")
        #expect(result.exitCode == 0)
        #expect(result.output.contains("video-review player seek <seconds|mm:ss>"))
    }

    @Test("a reply that doesn't read, or none in time, exits 1 saying why")
    func failures() {
        let run = Run { _, _ in .failure(.timedOut) }
        defer { run.cleanUp() }
        #expect(run("player", "play") == CommandResult(error: "\(AppIdentity.appName) didn't answer within 15 seconds\n", exitCode: 1))
        run.transport.answer = { _, _ in .failure(.failed("couldn't reach it")) }
        #expect(run("player", "play") == CommandResult(error: "couldn't ask \(AppIdentity.appName): couldn't reach it\n", exitCode: 1))
    }
}

@Suite("video-review app open and quit")
struct AppCommandTests {
    static let status = "running: \(AppIdentity.appName)\n"

    /// An app that runs on the support folders in `running`, quits when
    /// asked and starts on the launcher's folder when launched.
    final class FakeApps: @unchecked Sendable {
        /// The support folders' paths.
        var running: Set<String> = []

        func answer(_ message: ControlMessage, _ socket: URL) -> Result<ControlReply, ControlTransportFailure> {
            let support = socket.deletingLastPathComponent().standardizedFileURL.path
            guard running.contains(support) else { return .failure(.notRunning) }
            if message.request == .appQuit {
                running.remove(support)
                return .success(.done("quit\n"))
            }
            return .success(.done(AppCommandTests.status))
        }
    }

    private func makeRun(running: (Run) -> [URL]) -> (Run, FakeApps) {
        let apps = FakeApps()
        let run = Run { apps.answer($0, $1) }
        apps.running = Set(running(run).map(\.standardizedFileURL.path))
        run.launcher.launched = { environment in
            let support = environment[SupportFolder.overrideVariable].map { URL(fileURLWithPath: $0, isDirectory: true) } ?? run.support
            apps.running.insert(support.standardizedFileURL.path)
        }
        return (run, apps)
    }

    @Test("app open launches the app when it isn't running, and waits for it")
    func opens() {
        let (run, _) = makeRun { _ in [] }
        defer { run.cleanUp() }
        #expect(run("app", "open") == CommandResult(output: Self.status))
        #expect(run.launcher.launches == [[:]])
    }

    @Test("app open on a running app only asks it")
    func alreadyRunning() {
        let (run, _) = makeRun { [$0.support] }
        defer { run.cleanUp() }
        #expect(run("app", "open") == CommandResult(output: Self.status))
        #expect(run.launcher.launches.isEmpty)
        #expect(run.transport.requests == [.appOpen])
    }

    @Test("app open --demo quits the normal app and runs the app on the demo folder, which it makes")
    func opensDemo() throws {
        let (run, apps) = makeRun { [$0.support] }
        defer { run.cleanUp() }
        let demo = run.folder.appendingPathComponent("demo", isDirectory: true)
        #expect(run("app", "open", "--demo", demo.path) == CommandResult(output: Self.status))
        #expect(run.launcher.launches == [[SupportFolder.overrideVariable: demo.path]])
        #expect(apps.running == [demo.standardizedFileURL.path])
        #expect(FileManager.default.fileExists(atPath: demo.path))
        #expect(DemoPointer.recorded(in: run.support)?.path == demo.path)

        // Later commands reach the demo's socket once it's there.
        try Data().write(to: ControlSocket.url(in: demo))
        _ = run("player", "play")
        #expect(run.transport.sent.last?.socket.path == ControlSocket.url(in: demo).path)
    }

    @Test("app open --demo on the demo that already runs keeps it running")
    func sameDemo() {
        let demo = FileManager.default.temporaryDirectory.appendingPathComponent("video-review-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: demo) }
        let (run, apps) = makeRun { _ in [demo] }
        defer { run.cleanUp() }
        #expect(run("app", "open", "--demo", demo.path) == CommandResult(output: Self.status))
        #expect(run.launcher.launches.isEmpty)
        #expect(apps.running == [demo.standardizedFileURL.path])
    }

    @Test("plain app open quits a demo, removes its pointer and brings the normal app back")
    func backToNormal() throws {
        let (run, apps) = makeRun { [$0.folder.appendingPathComponent("demo", isDirectory: true)] }
        defer { run.cleanUp() }
        let demo = run.folder.appendingPathComponent("demo", isDirectory: true)
        try DemoPointer.record(demo, in: run.support)
        #expect(run("app", "open") == CommandResult(output: Self.status))
        #expect(DemoPointer.recorded(in: run.support) == nil)
        #expect(run.launcher.launches == [[:]])
        #expect(apps.running == [run.support.standardizedFileURL.path])
    }

    @Test("a demo that doesn't come to run leaves no pointer")
    func demoFails() {
        let (run, _) = makeRun { _ in [] }
        defer { run.cleanUp() }
        run.launcher.failure = AppLaunchFailure("the app isn't installed")
        let demo = run.folder.appendingPathComponent("demo", isDirectory: true)
        #expect(run("app", "open", "--demo", demo.path) == CommandResult(error: "video-review app open: the app isn't installed\n", exitCode: 1))
        #expect(DemoPointer.recorded(in: run.support) == nil)
    }

    @Test("an app that never answers after its launch exits 1")
    func neverAnswers() {
        let run = Run()
        defer { run.cleanUp() }
        let result = run("app", "open")
        #expect(result == CommandResult(error: "\(AppIdentity.appName) didn't answer within 10 seconds of launching\n", exitCode: 1))
    }

    @Test("app quit waits until the app is gone")
    func quits() {
        let (run, apps) = makeRun { [$0.support] }
        defer { run.cleanUp() }
        #expect(run("app", "quit") == CommandResult(output: "quit\n"))
        #expect(apps.running.isEmpty)
        #expect(run.transport.requests == [.appQuit, .appStatus])
    }
}
