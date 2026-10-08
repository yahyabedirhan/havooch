import Foundation
import ReviewSetup
import Synchronization
import Testing

@Suite("Installing the skill")
struct SkillInstallTests {
    static let codex = HarnessCatalog.harness(named: "codex")!
    static let pi = HarnessCatalog.harness(named: "pi")!

    @Test("the command is npx skills add for the skill, global, with -a for each harness")
    func commandLine() {
        let install = SkillInstall(for: [Self.codex, Self.pi])
        #expect(install.commandLine == "npx skills add yahyabedirhan/havooch-mate --skill havooch-mate -g -y -a codex -a pi")
        #expect(install.repositoryCommandLine == "npx skills add yahyabedirhan/havooch-mate --skill havooch-mate -y -a codex -a pi")
    }

    @Test("it finds npx in the login shell, runs the install there and streams its lines")
    func runs() async {
        let runner = FakeRunner { call in
            call.arguments.last == "command -v npx" ? (["/opt/homebrew/bin/npx"], 0) : (["Installing havooch-mate", "Done"], 0)
        }
        let lines = Mutex<[String]>([])
        let outcome = await SkillInstall(for: [Self.codex], shell: "/bin/zsh").run(with: runner) { line in
            lines.withLock { $0.append(line) }
        }
        #expect(outcome == .finished(status: 0))
        #expect(runner.calls == [
            .init(executable: "/bin/zsh", arguments: ["-l", "-c", "command -v npx"]),
            .init(executable: "/bin/zsh", arguments: ["-l", "-c", "exec env CI=true NO_COLOR=1 npx skills add yahyabedirhan/havooch-mate --skill havooch-mate -g -y -a codex"]),
        ])
        // The search for npx isn't the install's log.
        #expect(lines.withLock { $0 } == ["Installing havooch-mate", "Done"])
    }

    @Test("the CLI's spinner frames and escape codes reach the log as plain lines, the bare guide bars left out")
    func readableLines() async {
        let runner = FakeRunner { call in
            call.arguments.last == "command -v npx" ? ([], 0) : ([
                "\u{1B}[?25l\u{1B}[90m│\u{1B}[39m",
                "\u{1B}[?25h\u{1B}[?25l",
                "◒  Cloning repository...",
                "\u{1B}[1G\u{1B}[J◇  Repository cloned  ",
                "",
            ], 0)
        }
        let lines = Mutex<[String]>([])
        _ = await SkillInstall(for: [Self.codex]).run(with: runner) { line in lines.withLock { $0.append(line) } }
        #expect(lines.withLock { $0 } == ["◒  Cloning repository...", "◇  Repository cloned"])
    }

    @Test("a failed install ends with its exit status")
    func fails() async {
        let runner = FakeRunner { call in call.arguments.last == "command -v npx" ? ([], 0) : (["npm error 404"], 1) }
        #expect(await SkillInstall(for: [Self.codex]).run(with: runner) { _ in } == .finished(status: 1))
    }

    @Test("without npx it ends as no Node, and runs nothing")
    func noNode() async {
        let runner = FakeRunner { _ in ([], 1) }
        #expect(await SkillInstall(for: [Self.codex]).run(with: runner) { _ in } == .noNode)
        #expect(runner.calls.count == 1)
    }

    @Test("cancelling stops the running install")
    func cancels() async throws {
        let runner = FakeRunner(holds: true) { _ in (["Installing havooch-mate"], 0) }
        let task = Task { await SkillInstall(for: [Self.codex]).run(with: runner) { _ in } }
        while !runner.isHolding { try await Task.sleep(for: .milliseconds(5)) }
        task.cancel()
        #expect(await task.value == .cancelled)
    }
}

@Suite("Running a program")
struct LocalProcessRunnerTests {
    @Test("each line the program writes comes as it is written, standard error with it, and the exit status at the end")
    func lines() async {
        let lines = Mutex<[String]>([])
        let status = await LocalProcessRunner().run("/bin/sh", arguments: ["-c", "echo one; echo two >&2; printf three; exit 3"]) { line in
            lines.withLock { $0.append(line) }
        }
        #expect(status == 3)
        #expect(lines.withLock { $0 } == ["one", "two", "three"])
    }

    @Test("cancelling stops the program")
    func cancel() async throws {
        let started = Date()
        let task = Task { await LocalProcessRunner().run("/bin/sh", arguments: ["-c", "echo started; exec sleep 30"]) { _ in } }
        try await Task.sleep(for: .milliseconds(200))
        task.cancel()
        #expect(await task.value != 0)
        #expect(Date().timeIntervalSince(started) < 10)
    }

    @Test("a program that can't start ends at once with a line saying why")
    func cannotStart() async {
        let lines = Mutex<[String]>([])
        let status = await LocalProcessRunner().run("/nowhere/npx", arguments: []) { line in lines.withLock { $0.append(line) } }
        #expect(status == 127)
        #expect(lines.withLock { $0 }.count == 1)
    }
}
