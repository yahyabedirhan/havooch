import Foundation
import ReviewCommand
import ReviewLease
import ReviewWire
import Testing

@Suite("The video-review command")
struct CommandTests {
    @Test("each command sends its request", arguments: [
        (["state"], ControlRequest.state),
        (["control", "take"], .controlTake(waitSeconds: nil)),
        (["control", "take", "--wait", "30"], .controlTake(waitSeconds: 30)),
        (["control", "release"], .controlRelease),
        (["screenshot", "/tmp/shot.png", "--with-banner"], .screenshot(path: "/tmp/shot.png", appearance: nil, withBanner: true)),
        (["player", "open", "/videos/sample.mp4"], .playerOpen(path: "/videos/sample.mp4")),
        (["player", "open", "clips/../sample.mp4"], .playerOpen(path: "/Users/me/shop/sample.mp4")),
        (["player", "play"], .playerPlay),
        (["player", "pause"], .playerPause),
        (["player", "seek", "0:10"], .playerSeek(seconds: 10)),
        (["player", "seek", "12.5"], .playerSeek(seconds: 12.5)),
        (["screenshot", "/tmp/shot.png"], .screenshot(path: "/tmp/shot.png", appearance: nil)),
        (["screenshot", "/tmp/shot.png", "--appearance", "dark"], .screenshot(path: "/tmp/shot.png", appearance: .dark)),
        (["screenshot", "--appearance", "light", "/tmp/shot.png"], .screenshot(path: "/tmp/shot.png", appearance: .light)),
        (["comment", "add", "Too fast here"], .commentAdd(text: "Too fast here", at: nil)),
        (["comment", "add", "Too fast here", "--at", "0:10"], .commentAdd(text: "Too fast here", at: 10)),
        (["comment", "add", "--at", "12.5", "Too fast here"], .commentAdd(text: "Too fast here", at: 12.5)),
        (["comment", "add", "This box", "--region", "0.25,0.2,0.3,0.25"],
         .commentAdd(text: "This box", at: nil, region: .init(x: 0.25, y: 0.2, w: 0.3, h: 0.25))),
        (["comment", "add", "--region", "0,0,1,1", "This box", "--at", "0:10"],
         .commentAdd(text: "This box", at: 10, region: .init(x: 0, y: 0, w: 1, h: 1))),
        (["comment", "edit", "c-7f3a9c2e", "Slower here"], .commentEdit(id: "c-7f3a9c2e", text: "Slower here")),
        (["comment", "delete", "c-7f3a9c2e"], .commentDelete(id: "c-7f3a9c2e")),
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

    @Test("a second holder exits 1 with the lease's refusal, which names the holder and the lease's end, on standard error")
    func leaseRefused() throws {
        // What the app answers a second holder: the lease's own words.
        var lease = ControlLease()
        let first = Holder(key: "agent-1", name: "Claude Code", place: "/Users/me/shop")
        _ = lease.use(by: first, at: Date(timeIntervalSince1970: 0))
        let refused = lease.use(by: Holder(key: "agent-2", name: "codex", place: "/work"), at: Date(timeIntervalSince1970: 12.5))
        guard case .failure(let refusal) = refused.answer else { Issue.record("not refused"); return }
        let line = refusal.message(at: Date(timeIntervalSince1970: 12.5), timeZone: try #require(TimeZone(identifier: "UTC")))
        let run = Run { _, _ in .success(.refused(line)) }
        defer { run.cleanUp() }

        for arguments in [["player", "play"], ["control", "take"], ["screenshot", "/tmp/shot.png"]] {
            let result = VideoReviewCLI.run(arguments, environment: run.environment)
            #expect(result.exitCode == 1)
            #expect(result.output.isEmpty)
            #expect(result.error == "\(AppIdentity.appName) is in use by Claude Code in /Users/me/shop until 00:01:00 (48s left); "
                + "`video-review control take --wait <seconds>` to queue\n")
        }
    }

    @Test("the holder key is VIDEO_REVIEW_CONTROL_KEY when set, else the Claude Code session, else the ancestor process")
    func holderKey() {
        struct Processes: ProcessTable {
            var currentPID: Int32 { 300 }
            func process(_ pid: Int32) -> ProcessRecord? {
                let started = Date(timeIntervalSince1970: 1_700_000_000)
                return [
                    300: ProcessRecord(pid: 300, parent: 200, started: started, name: "video-review"),
                    200: ProcessRecord(pid: 200, parent: 100, started: started, name: "zsh"),
                    100: ProcessRecord(pid: 100, parent: 1, started: started, name: "codex"),
                ][pid]
            }
        }
        let run = Run { _, _ in .success(.done("done\n")) }
        defer { run.cleanUp() }
        for variables in [
            ["CLAUDE_CODE_SESSION_ID": "abc", "VIDEO_REVIEW_CONTROL_KEY": "holder-a"], ["CLAUDE_CODE_SESSION_ID": "abc"], [:],
        ] {
            var environment = run.environment
            environment.variables = variables.merging([SupportFolder.overrideVariable: run.support.path]) { _, new in new }
            environment.processes = Processes()
            _ = VideoReviewCLI.run(["control", "take"], environment: environment)
        }
        #expect(run.transport.sent.map(\.message.holder.key) == ["holder-a", "CLAUDE_CODE_SESSION_ID=abc", "process:100@1700000000000000"])
    }

    @Test("a take that waits in line gets its wait on top of the usual time to answer")
    func takeWaits() {
        let run = Run { _, _ in .failure(.timedOut) }
        defer { run.cleanUp() }
        #expect(run("control", "take", "--wait", "30")
            == CommandResult(error: "\(AppIdentity.appName) didn't answer within 45 seconds\n", exitCode: 1))
    }

    @Test("every command but app status and app open exits 1 when the app isn't running")
    func notRunning() {
        let run = Run()
        defer { run.cleanUp() }
        let line = "\(AppIdentity.appName) isn't running; run `video-review app open`\n"
        #expect(run("player", "play") == CommandResult(error: line, exitCode: 1))
        #expect(run("control", "take", "--wait", "5") == CommandResult(error: line, exitCode: 1))
        #expect(run("control", "release") == CommandResult(error: line, exitCode: 1))
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
        ["control"], ["control", "steal"], ["control", "take", "--wait"], ["control", "take", "--wait", "soon"],
        ["control", "take", "--wait", "-1"], ["control", "take", "--wait", "3601"], ["control", "take", "now"],
        ["control", "release", "--wait", "5"], ["player", "play", "--with-banner"],
        ["comment"], ["comment", "add"], ["comment", "add", "Too", "fast"], ["comment", "add", "Too fast", "--at", "soon"],
        ["comment", "add", "Too fast", "--at"], ["comment", "add", "This box", "--region"],
        ["comment", "add", "This box", "--region", "0.25,0.2,0.3"], ["comment", "add", "This box", "--region", "left,top,0.3,0.25"],
        ["comment", "edit"], ["comment", "edit", "c-7f3a9c2e"],
        ["comment", "edit", "c-7f3a9c2e", "Slower", "here"], ["comment", "delete"], ["comment", "delete", "c-1", "c-2"],
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
        /// The lease the app's reply to a quit carries.
        var lease: LeaseTerm?

        func answer(_ message: ControlMessage, _ socket: URL) -> Result<ControlReply, ControlTransportFailure> {
            let support = socket.deletingLastPathComponent().standardizedFileURL.path
            guard running.contains(support) else { return .failure(.notRunning) }
            if message.request == .appQuit {
                running.remove(support)
                return .success(ControlReply(ok: true, output: "quit\n", lease: lease))
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

    @Test("app open --demo on a running app hands the lease its quit renewed to the app it launches, and so does going back")
    func relaunchKeepsTheLease() throws {
        let (run, apps) = makeRun { [$0.support] }
        defer { run.cleanUp() }
        let term = LeaseTerm(
            holder: Holder(key: "CLAUDE_CODE_SESSION_ID=abc", name: "Claude Code", place: "/Users/me/shop"),
            taken: Date(timeIntervalSince1970: 0), ends: Date(timeIntervalSince1970: 80)
        )
        apps.lease = term
        let demo = run.folder.appendingPathComponent("demo", isDirectory: true)

        #expect(run("app", "open", "--demo", demo.path) == CommandResult(output: Self.status))
        #expect(run("app", "open") == CommandResult(output: Self.status))

        let handover = try #require(ControlLease.handover(term).first)
        #expect(run.launcher.launches == [
            [SupportFolder.overrideVariable: demo.path, handover.key: handover.value],
            [handover.key: handover.value],
        ])
        #expect(ControlLease(environment: run.launcher.launches[0], at: Date(timeIntervalSince1970: 30))
            .current(at: Date(timeIntervalSince1970: 30)) == term)
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
