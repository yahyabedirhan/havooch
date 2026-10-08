import Foundation
import ReviewCommand
import ReviewLease
import ReviewWire
import Synchronization
import Testing

@Suite("The havooch command")
struct CommandTests {
    @Test("each command sends its request", arguments: [
        (["state"], ControlRequest.state),
        (["app", "home"], .appHome),
        (["app", "demo"], .appDemo),
        (["control", "take"], .controlTake(waitSeconds: nil)),
        (["control", "take", "--wait", "30"], .controlTake(waitSeconds: 30)),
        (["control", "release"], .controlRelease),
        (["screenshot", "/tmp/shot.png", "--hide-agent-indicator"], .screenshot(path: "/tmp/shot.png", appearance: nil, hideAgentIndicator: true)),
        (["player", "open", "/videos/sample.mp4"], .playerOpen(path: "/videos/sample.mp4")),
        (["player", "open", "clips/../sample.mp4"], .playerOpen(path: "/Users/me/shop/sample.mp4")),
        (["player", "play"], .playerPlay),
        (["player", "pause"], .playerPause),
        (["player", "seek", "0:10"], .playerSeek(seconds: 10)),
        (["player", "seek", "12.5"], .playerSeek(seconds: 12.5)),
        (["screenshot", "/tmp/shot.png"], .screenshot(path: "/tmp/shot.png", appearance: nil)),
        (["screenshot", "/tmp/shot.png", "--appearance", "dark"], .screenshot(path: "/tmp/shot.png", appearance: .dark)),
        (["screenshot", "--appearance", "light", "/tmp/shot.png"], .screenshot(path: "/tmp/shot.png", appearance: .light)),
        (["screenshot", "/tmp/set.png", "--window", "settings"], .screenshot(path: "/tmp/set.png", appearance: nil, window: .settings)),
        (["screenshot", "/tmp/about.png", "--window", "about"], .screenshot(path: "/tmp/about.png", appearance: nil, window: .about)),
        (["screenshot", "/tmp/shot.png", "--window", "main"], .screenshot(path: "/tmp/shot.png", appearance: nil)),
        (["comment", "add", "Too fast here"], .commentAdd(text: "Too fast here", at: nil)),
        (["comment", "add", "Too fast here", "--at", "0:10"], .commentAdd(text: "Too fast here", at: 10)),
        (["comment", "add", "--at", "12.5", "Too fast here"], .commentAdd(text: "Too fast here", at: 12.5)),
        (["comment", "add", "This box", "--region", "0.25,0.2,0.3,0.25"],
         .commentAdd(text: "This box", at: nil, region: .init(x: 0.25, y: 0.2, w: 0.3, h: 0.25))),
        (["comment", "add", "--region", "0,0,1,1", "This box", "--at", "0:10"],
         .commentAdd(text: "This box", at: 10, region: .init(x: 0, y: 0, w: 1, h: 1))),
        (["comment", "add", "Follow-up", "--thread", "t-f92cbb2a-1"], .commentAdd(text: "Follow-up", at: nil, thread: "t-f92cbb2a-1")),
        (["comment", "add", "--thread", "0", "In general"], .commentAdd(text: "In general", at: nil, thread: "0")),
        (["comment", "edit", "m-f92cbb2a-1", "Slower here"], .commentEdit(id: "m-f92cbb2a-1", text: "Slower here")),
        (["comment", "delete", "m-f92cbb2a-1"], .commentDelete(id: "m-f92cbb2a-1")),
        (["comment", "open"], .commentOpen(text: "")),
        (["comment", "open", "Too fast", "--region", "0.25,0.2,0.3,0.25"],
         .commentOpen(text: "Too fast", region: .init(x: 0.25, y: 0.2, w: 0.3, h: 0.25))),
        (["comment", "compose"], .commentCompose(text: "")),
        (["comment", "compose", "Too fast", "--region", "0.25,0.2,0.3,0.25"],
         .commentCompose(text: "Too fast", region: .init(x: 0.25, y: 0.2, w: 0.3, h: 0.25))),
        (["comment", "compose", "--general", "Overall"], .commentCompose(text: "Overall", general: true)),
        (["context", "set", "Compare with the old cut"], .contextSet(text: "Compare with the old cut")),
        (["context", "set", ""], .contextSet(text: "")),
        (["send"], .send),
        (["wait"], .wait(timeoutSeconds: nil)),
        (["wait", "--timeout", "0"], .wait(timeoutSeconds: 0)),
        (["ack", "s-f92cbb2a-1"], .ack(sendID: "s-f92cbb2a-1", text: nil)),
        (["ack", "s-f92cbb2a-1", "On it"], .ack(sendID: "s-f92cbb2a-1", text: "On it")),
        (["status", "m-f92cbb2a-1", "working"], .status(messageID: "m-f92cbb2a-1", state: .working)),
        (["status", "m-f92cbb2a-1", "done"], .status(messageID: "m-f92cbb2a-1", state: .done)),
        (["status", "m-f92cbb2a-1", "failed"], .status(messageID: "m-f92cbb2a-1", state: .failed)),
        (["status", "m-f92cbb2a-1", "working", "Rendering 0:14 to 0:21"],
         .status(messageID: "m-f92cbb2a-1", state: .working, text: "Rendering 0:14 to 0:21")),
        (["reply", "t-f92cbb2a-1", "Slowed it down"], .reply(thread: "t-f92cbb2a-1", text: "Slowed it down")),
        (["reply", "0", "All done"], .reply(thread: "0", text: "All done")),
        (["ask", "t-f92cbb2a-1", "Which part?"], .ask(thread: "t-f92cbb2a-1", question: "Which part?", waitSeconds: nil)),
        (["ask", "t-f92cbb2a-1", "Which part?", "--wait", "30"], .ask(thread: "t-f92cbb2a-1", question: "Which part?", waitSeconds: 30)),
        (["ask", "--wait", "0", "t-f92cbb2a-1", "Which part?"], .ask(thread: "t-f92cbb2a-1", question: "Which part?", waitSeconds: 0)),
        (["ask", "1", "Which part?", "--choice", "The intro", "--wait", "30", "--choice", "The end"],
         .ask(thread: "1", question: "Which part?", waitSeconds: 30, choices: ["The intro", "The end"])),
        (["thread", "answer", "t-f92cbb2a-1", "The intro"], .threadAnswer(thread: "t-f92cbb2a-1", text: "The intro")),
        (["thread", "choose", "t-f92cbb2a-1", "2"], .threadChoose(thread: "t-f92cbb2a-1", choice: 2)),
        (["thread", "open", "3"], .threadOpen(thread: "3")),
        (["thread", "open", "t-f92cbb2a-3", "--frame", "0.55,0.1,0.4,0.5"],
         .threadOpen(thread: "t-f92cbb2a-3", frame: .init(x: 0.55, y: 0.1, w: 0.4, h: 0.5))),
        (["thread", "show", "3"], .threadShow(thread: "3")),
        (["thread", "list"], .threadList),
    ])
    func sends(arguments: [String], request: ControlRequest) {
        let run = Run { _, _ in .success(.done("done\n")) }
        defer { run.cleanUp() }
        let result = HavoochCLI.run(arguments, environment: run.environment)
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

    @Test("a second holder exits 1 with the lease's refusal, which names the holder and the lease's end, on standard error", arguments: [
        ["player", "play"], ["control", "take"], ["screenshot", "/tmp/shot.png"],
    ])
    func leaseRefused(arguments: [String]) throws {
        // What the app answers a second holder: the lease's own words.
        var lease = ControlLease()
        let first = Holder(key: "agent-1", name: "Claude Code", place: "/Users/me/shop")
        _ = lease.use(by: first, at: Date(timeIntervalSince1970: 0))
        let refused = lease.use(by: Holder(key: "agent-2", name: "codex", place: "/work"), at: Date(timeIntervalSince1970: 12.5))
        guard case .failure(let refusal) = refused.answer else { Issue.record("not refused"); return }
        let line = refusal.message(at: Date(timeIntervalSince1970: 12.5), timeZone: try #require(TimeZone(identifier: "UTC")))
        let run = Run { _, _ in .success(.refused(line)) }
        defer { run.cleanUp() }

        let result = HavoochCLI.run(arguments, environment: run.environment)
        #expect(result.exitCode == 1)
        #expect(result.output.isEmpty)
        #expect(result.error == "\(AppIdentity.appName) is in use by Claude Code in /Users/me/shop until 00:01:00 (48s left); "
            + "`havooch control take --wait <seconds>` to queue\n")
    }

    @Test(
        "the holder key is HAVOOCH_CONTROL_KEY when set, else the Claude Code, Codex or Pi session, else the ancestor process",
        arguments: [
            (["CLAUDE_CODE_SESSION_ID": "abc", "HAVOOCH_CONTROL_KEY": "holder-a"], "holder-a", "Claude Code"),
            (["CLAUDE_CODE_SESSION_ID": "abc"], "CLAUDE_CODE_SESSION_ID=abc", "Claude Code"),
            (["CODEX_THREAD_ID": "019a-thread"], "CODEX_THREAD_ID=019a-thread", "Codex"),
            (["CODEX_THREAD_ID": "019a-thread", "HAVOOCH_CONTROL_KEY": "holder-b"], "holder-b", "Codex"),
            (["PI_SESSION_ID": "pi-1"], "PI_SESSION_ID=pi-1", "Pi"),
            ([:], "process:100@1700000000000000", "codex"),
        ] as [([String: String], String, String)]
    )
    func holderKey(variables: [String: String], key: String, name: String) {
        struct Processes: ProcessTable {
            var currentPID: Int32 { 300 }
            func process(_ pid: Int32) -> ProcessRecord? {
                let started = Date(timeIntervalSince1970: 1_700_000_000)
                return [
                    300: ProcessRecord(pid: 300, parent: 200, started: started, name: "havooch"),
                    200: ProcessRecord(pid: 200, parent: 100, started: started, name: "zsh"),
                    100: ProcessRecord(pid: 100, parent: 1, started: started, name: "codex"),
                ][pid]
            }
        }
        let run = Run { _, _ in .success(.done("done\n")) }
        defer { run.cleanUp() }
        var environment = run.environment
        environment.variables = variables.merging([SupportFolder.overrideVariable: run.support.path]) { _, new in new }
        environment.processes = Processes()
        _ = HavoochCLI.run(["control", "take"], environment: environment)
        #expect(run.transport.sent.map(\.message.holder.key) == [key])
        #expect(run.transport.sent.map(\.message.holder.name) == [name])
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
        let line = "\(AppIdentity.appName) isn't running; run `havooch app open`\n"
        #expect(run("player", "play") == CommandResult(error: line, exitCode: 1))
        #expect(run("control", "take", "--wait", "5") == CommandResult(error: line, exitCode: 1))
        #expect(run("control", "release") == CommandResult(error: line, exitCode: 1))
        #expect(run("state", "--json") == CommandResult(error: line, exitCode: 1))
        #expect(run("app", "quit") == CommandResult(error: line, exitCode: 1))
        #expect(run("app", "home") == CommandResult(error: line, exitCode: 1))
        #expect(run("app", "demo") == CommandResult(error: line, exitCode: 1))
        #expect(run("app", "status") == CommandResult(output: "not running\n"))
        #expect(run("app", "status", "--json") == CommandResult(output: "{\"running\":false}\n"))
    }

    @Test("arguments that don't read exit 64 and send nothing", arguments: [
        [], ["rewind"], ["player"], ["player", "rewind"], ["player", "seek"], ["player", "seek", "soon"],
        ["player", "seek", "-5"], ["player", "seek", "1", "2"], ["player", "seek", String(repeating: "9", count: 400)],
        ["comment", "add", "Too fast", "--at", String(repeating: "9", count: 400) + ":00"], ["comment", "add", "--", "Too fast", "--at", "5"], ["player", "open"], ["player", "play", "now"],
        ["screenshot"], ["screenshot", "shot.png"], ["screenshot", "/tmp/shot.jpg"],
        ["screenshot", "/tmp/shot.png", "--appearance", "sepia"], ["screenshot", "/tmp/shot.png", "--appearance"],
        ["screenshot", "/tmp/shot.png", "--window", "inspector"],
        ["state", "--verbose"], ["app", "open", "--demo"], ["app", "status", "now"], ["app", "home", "now"], ["app", "demo", "sample.mp4"],
        ["control"], ["control", "steal"], ["control", "take", "--wait"], ["control", "take", "--wait", "soon"],
        ["control", "take", "--wait", "-1"], ["control", "take", "--wait", "3601"], ["control", "take", "now"],
        ["control", "release", "--wait", "5"], ["player", "play", "--hide-agent-indicator"],
        ["comment"], ["comment", "add"], ["comment", "add", "Too", "fast"], ["comment", "add", "Too fast", "--at", "soon"],
        ["comment", "add", "Too fast", "--at"], ["comment", "add", "This box", "--region"],
        ["comment", "add", "This box", "--region", "0.25,0.2,0.3"], ["comment", "add", "This box", "--region", "left,top,0.3,0.25"],
        ["comment", "edit"], ["comment", "edit", "m-f92cbb2a-1"],
        ["comment", "edit", "m-f92cbb2a-1", "Slower", "here"], ["comment", "delete"], ["comment", "delete", "m-1", "m-2"],
        ["context"], ["context", "set"], ["context", "set", "two", "words"], ["context", "get"],
        ["batch", "send"], ["send", "now"], ["send", "--timeout", "5"], ["comment", "add", "x", "--thread"], ["comment", "open", "two", "words"], ["comment", "open", "--region", "1,2"],
        ["wait", "now"], ["wait", "--timeout"], ["wait", "--timeout", "soon"], ["wait", "--timeout", "-1"],
        ["wait", "--timeout", "86401"], ["wait", "--wait", "5"],
        ["ack"], ["ack", "s-f92cbb2a-1", "On", "it"], ["ack", "s-f92cbb2a-1", "--wait", "5"],
        ["status"], ["status", "m-f92cbb2a-1"], ["status", "m-f92cbb2a-1", "acknowledged"], ["status", "m-f92cbb2a-1", "sent"],
        ["status", "m-f92cbb2a-1", "done", "now"], ["status", "m-f92cbb2a-1", "failed", "now"],
        ["status", "m-f92cbb2a-1", "working", "Rendering", "now"],
        ["reply"], ["reply", "t-f92cbb2a-1"], ["reply", "t-f92cbb2a-1", "Slowed", "it"],
        ["ask"], ["ask", "t-f92cbb2a-1"], ["ask", "t-f92cbb2a-1", "Which part?", "--wait"],
        ["ask", "t-f92cbb2a-1", "Which part?", "--wait", "soon"], ["ask", "t-f92cbb2a-1", "Which part?", "--wait", "-1"],
        ["ask", "t-f92cbb2a-1", "Which part?", "--wait", "86401"], ["ask", "t-f92cbb2a-1", "Which part?", "--timeout", "5"],
        ["thread"], ["thread", "answer"], ["thread", "answer", "t-f92cbb2a-1"], ["thread", "answer", "t-f92cbb2a-1", "The", "intro"],
        ["ask", "1", "Which part?", "--choice"],
        ["thread", "choose"], ["thread", "choose", "1"], ["thread", "choose", "1", "0"], ["thread", "choose", "1", "first"],
        ["thread", "choose", "1", "2", "3"],
        ["thread", "open"], ["thread", "open", "1", "2"], ["thread", "open", "1", "--frame"], ["thread", "open", "1", "--frame", "1,2"],
    ])
    func usage(arguments: [String]) {
        let run = Run { _, _ in .success(.done("done\n")) }
        defer { run.cleanUp() }
        let result = HavoochCLI.run(arguments, environment: run.environment)
        #expect(result.exitCode == 64)
        #expect(result.output.isEmpty)
        #expect(result.error.contains("usage: havooch"))
        #expect(run.transport.sent.isEmpty)
        #expect(run.launcher.launches.isEmpty)
    }

    // MARK: - wait

    /// The time `wait` counts by, moved on by each of its rests.
    final class Clock: Sendable {
        private let time = Mutex(Date(timeIntervalSince1970: 0))

        var now: Date {
            get { time.withLock { $0 } }
            set { time.withLock { $0 = newValue } }
        }
    }

    /// `run`'s environment with a clock that only the command's rests move.
    private func timed(_ run: Run, _ clock: Clock) -> CommandEnvironment {
        var environment = run.environment
        environment.now = { clock.now }
        environment.pause = { clock.now += $0 }
        return environment
    }

    @Test("wait prints the send the app answers with as it is, exit 0, and may be held for its whole timeout")
    func waitPrints() {
        let payload = "{\n  \"send\" : {\n    \"id\" : \"s-f92cbb2a-1\"\n  }\n}\n"
        let run = Run { _, _ in .success(.done(payload)) }
        defer { run.cleanUp() }
        #expect(run("wait", "--timeout", "600") == CommandResult(output: payload))
        #expect(run.transport.requests == [.wait(timeoutSeconds: 600)])
        #expect(run.transport.requests[0].holdSeconds == 600)
    }

    @Test("a wait whose timeout runs out exits 2 with nothing on standard output")
    func waitRunsOut() {
        let run = Run { _, _ in .success(.ranOut) }
        defer { run.cleanUp() }
        #expect(run("wait", "--timeout", "5") == CommandResult(exitCode: 2))
        #expect(run("wait", "--timeout", "5", "--json") == CommandResult(exitCode: 2))
    }

    @Test("a wait the app refuses exits 1 with the reason")
    func waitRefused() {
        let run = Run { _, _ in .success(.refused("a newer `havooch wait` took this one's place: one listener at a time")) }
        defer { run.cleanUp() }
        #expect(run("wait") == CommandResult(
            error: "a newer `havooch wait` took this one's place: one listener at a time\n", exitCode: 1
        ))
    }

    @Test("wait connects again each second while the app isn't running, and asks only for the time it has left")
    func waitBeforeTheApp() {
        let clock = Clock()
        let run = Run { _, _ in clock.now < Date(timeIntervalSince1970: 3) ? .failure(.notRunning) : .success(.done("{}\n")) }
        defer { run.cleanUp() }
        #expect(HavoochCLI.run(["wait", "--timeout", "10"], environment: timed(run, clock)) == CommandResult(output: "{}\n"))
        #expect(run.transport.requests == [
            .wait(timeoutSeconds: 10), .wait(timeoutSeconds: 9), .wait(timeoutSeconds: 8), .wait(timeoutSeconds: 7),
        ])
    }

    @Test("a wait with a timeout gives up, exit 2, when the app never runs; one without keeps looking")
    func waitWithoutTheApp() {
        let clock = Clock()
        let run = Run()
        defer { run.cleanUp() }
        #expect(HavoochCLI.run(["wait", "--timeout", "3"], environment: timed(run, clock)) == CommandResult(exitCode: 2))
        #expect(clock.now == Date(timeIntervalSince1970: 3))

        let later = Clock()
        let patient = Run { _, _ in later.now < Date(timeIntervalSince1970: 120) ? .failure(.notRunning) : .success(.done("{}\n")) }
        defer { patient.cleanUp() }
        #expect(HavoochCLI.run(["wait"], environment: timed(patient, later)) == CommandResult(output: "{}\n"))
        #expect(patient.transport.requests.last == .wait(timeoutSeconds: nil))
    }

    @Test("a wait started before a demo runs finds the demo's app once its pointer and socket are there")
    func waitFollowsTheDemo() throws {
        let clock = Clock()
        let run = Run()
        defer { run.cleanUp() }
        let demo = run.folder.appendingPathComponent("demo", isDirectory: true)
        run.transport.answer = { _, socket in
            if clock.now == Date(timeIntervalSince1970: 1), DemoPointer.recorded(in: run.support) == nil {
                // The demo starts while the command rests.
                try? FileManager.default.createDirectory(at: demo, withIntermediateDirectories: true)
                try? FileManager.default.createDirectory(at: run.support, withIntermediateDirectories: true)
                try? DemoPointer.record(demo, in: run.support)
                try? Data().write(to: ControlSocket.url(in: demo))
            }
            return socket.path == ControlSocket.url(in: demo).path ? .success(.done("{}\n")) : .failure(.notRunning)
        }
        #expect(HavoochCLI.run(["wait"], environment: timed(run, clock)) == CommandResult(output: "{}\n"))
        #expect(run.transport.sent.last?.socket.path == ControlSocket.url(in: demo).path)
    }

    // MARK: - ask

    @Test("ask prints the person's answer, exit 0, and may be held for its whole wait, or with no limit without one")
    func askPrintsTheAnswer() {
        let run = Run { _, _ in .success(.done("The intro\n")) }
        defer { run.cleanUp() }
        #expect(run("ask", "t-f92cbb2a-1", "Which part?", "--wait", "600") == CommandResult(output: "The intro\n"))
        #expect(run("ask", "t-f92cbb2a-1", "Which part?") == CommandResult(output: "The intro\n"))
        #expect(run.transport.sent.map(\.message.request.holdSeconds) == [600, nil])
    }

    @Test("an ask whose wait runs out exits 2 with nothing printed; a refused one exits 1 with the reason")
    func askRunsOutOrIsRefused() {
        let ranOut = Run { _, _ in .success(.ranOut) }
        defer { ranOut.cleanUp() }
        #expect(ranOut("ask", "t-f92cbb2a-1", "Which part?", "--wait", "5") == CommandResult(exitCode: 2))
        #expect(ranOut("ask", "t-f92cbb2a-1", "Which part?", "--wait", "5", "--json") == CommandResult(exitCode: 2))

        let line = "c-7f3a9c2e already has an open question"
        let refused = Run { _, _ in .success(.refused(line)) }
        defer { refused.cleanUp() }
        #expect(refused("ask", "t-f92cbb2a-1", "And how?") == CommandResult(error: line + "\n", exitCode: 1))
        #expect(refused("status", "m-f92cbb2a-1", "working") == CommandResult(error: line + "\n", exitCode: 1))
    }

    @Test("--help prints the usage on standard output, and so do -h and --help with --json or before a command's name", arguments: [
        ["--help"], ["-h"], ["--json", "--help"], ["--help", "comment", "add"],
    ])
    func help(arguments: [String]) {
        let run = Run()
        defer { run.cleanUp() }
        #expect(HavoochCLI.run(arguments, environment: run.environment) == CommandResult(output: CommandTable.usageText))
        #expect(CommandTable.usageText.contains("havooch player seek <seconds|mm:ss>"))
        #expect(CommandTable.usageText.contains("havooch app home "))
        #expect(CommandTable.usageText.contains("havooch app demo "))
        #expect(run.transport.sent.isEmpty)
    }

    @Test("--version prints 0.3.0 without asking the app, as JSON with --json")
    func version() {
        let run = Run()
        defer { run.cleanUp() }
        #expect(HavoochCLI.run(["--version"], environment: run.environment) == CommandResult(output: "0.3.0\n"))
        #expect(HavoochCLI.run(["--version", "--json"], environment: run.environment)
            == CommandResult(output: "{\n  \"version\" : \"0.3.0\"\n}\n"))
        #expect(run.transport.sent.isEmpty)
    }

    @Test("a text that looks like an option is a word: with a space in it, after --, or -h after the command's name", arguments: [
        (["reply", "t-f92cbb2a-1", "--region now takes pixels"], ControlRequest.reply(thread: "t-f92cbb2a-1", text: "--region now takes pixels")),
        (["comment", "add", "--at is wrong here", "--at", "5"], .commentAdd(text: "--at is wrong here", at: 5)),
        (["comment", "add", "--json is the default now"], .commentAdd(text: "--json is the default now", at: nil)),
        (["comment", "add", "-h"], .commentAdd(text: "-h", at: nil)),
        (["reply", "t-f92cbb2a-1", "-h"], .reply(thread: "t-f92cbb2a-1", text: "-h")),
        (["reply", "t-f92cbb2a-1", "--", "--region"], .reply(thread: "t-f92cbb2a-1", text: "--region")),
        (["reply", "--", "t-f92cbb2a-1", "--help"], .reply(thread: "t-f92cbb2a-1", text: "--help")),
        (["comment", "add", "--at", "5", "--", "--json"], .commentAdd(text: "--json", at: 5)),
        (["context", "set", "--", "--"], .contextSet(text: "--")),
    ])
    func optionLikeText(arguments: [String], request: ControlRequest) {
        let run = Run { _, _ in .success(.done("done\n")) }
        defer { run.cleanUp() }
        let result = HavoochCLI.run(arguments, environment: run.environment)
        #expect(result == CommandResult(output: "done\n"))
        #expect(run.transport.requests == [request])
        // The text's `--json` isn't the command's.
        #expect(run.transport.sent.map(\.message.json) == [false])
    }

    @Test("an option is an option wherever it's written before --, and --json after -- is a word")
    func optionsAnywhere() {
        let run = Run { _, _ in .success(.done("{}\n")) }
        defer { run.cleanUp() }
        _ = run("comment", "add", "Too fast here", "--at", "5", "--json")
        _ = run("comment", "add", "--json", "--at", "5", "--", "Too fast here")
        #expect(run.transport.requests == [.commentAdd(text: "Too fast here", at: 5), .commentAdd(text: "Too fast here", at: 5)])
        #expect(run.transport.sent.map(\.message.json) == [true, true])
        // A word too many is still refused, also after --.
        #expect(run("reply", "t-f92cbb2a-1", "--", "--region", "--json").exitCode == 64)
        #expect(run("reply", "t-f92cbb2a-1", "--region").exitCode == 64)
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

@Suite("havooch app open and quit")
struct AppCommandTests {
    static let status = "running: \(AppIdentity.appName)\n"

    /// An app that runs on the support folders in `running`, quits when
    /// asked and starts on the launcher's folder when launched.
    final class FakeApps: Sendable {
        private struct State {
            var running: Set<String> = []
            var lease: LeaseTerm?
        }

        private let state = Mutex(State())

        /// The support folders' paths.
        var running: Set<String> {
            get { state.withLock { $0.running } }
            set { state.withLock { $0.running = newValue } }
        }

        /// The lease the app's reply to a quit carries.
        var lease: LeaseTerm? {
            get { state.withLock { $0.lease } }
            set { state.withLock { $0.lease = newValue } }
        }

        func answer(_ message: ControlMessage, _ socket: URL) -> Result<ControlReply, ControlTransportFailure> {
            let support = socket.deletingLastPathComponent().standardizedFileURL.path
            return state.withLock { apps -> Result<ControlReply, ControlTransportFailure> in
                guard apps.running.contains(support) else { return .failure(.notRunning) }
                if message.request == .appQuit {
                    apps.running.remove(support)
                    return .success(ControlReply(ok: true, output: "quit\n", lease: apps.lease))
                }
                return .success(.done(AppCommandTests.status))
            }
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
        #expect(run.launcher.launches == [[SupportFolder.overrideVariable: demo.path, SupportFolder.demoRunVariable: "1"]])
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
            [SupportFolder.overrideVariable: demo.path, SupportFolder.demoRunVariable: "1", handover.key: handover.value],
            [handover.key: handover.value],
        ])
        #expect(ControlLease(environment: run.launcher.launches[0], at: Date(timeIntervalSince1970: 30))
            .current(at: Date(timeIntervalSince1970: 30)) == term)
    }

    @Test("app open --demo on the demo that already runs keeps it running")
    func sameDemo() {
        let demo = FileManager.default.temporaryDirectory.appendingPathComponent("havooch-tests-\(UUID().uuidString)", isDirectory: true)
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
        #expect(run("app", "open", "--demo", demo.path) == CommandResult(error: "havooch app open: the app isn't installed\n", exitCode: 1))
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
