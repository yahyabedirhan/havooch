import Foundation
@testable import ReviewApp
import ReviewSetup
import ReviewWire
import Synchronization
import Testing

/// A file system in memory, as `lstat` reads each path; a link is followed
/// once. Paths in `failing` can't be made.
final class MemoryFileSystem: SetupFileSystem {
    let items: Mutex<[String: FileItem]>
    let failing: Set<String>

    init(_ items: [String: FileItem] = [:], failing: Set<String> = []) {
        self.items = Mutex(items)
        self.failing = failing
    }

    subscript(path: String) -> FileItem? { items.withLock { $0[path] } }

    func item(at path: String) -> FileItem { items.withLock { $0[path] ?? .missing } }

    func target(at path: String) -> FileItem {
        items.withLock { items in
            guard case .link(let destination) = items[path] ?? .missing else { return items[path] ?? .missing }
            return items[destination] ?? .missing
        }
    }

    func makeFolder(at path: String) throws {
        if failing.contains(path) { throw CocoaError(.fileWriteNoPermission) }
        items.withLock { $0[path] = .folder }
    }

    func makeLink(at path: String, to destination: String) throws {
        if failing.contains(path) { throw CocoaError(.fileWriteNoPermission) }
        items.withLock { $0[path] = .link(to: destination) }
    }

    func remove(at path: String) throws { items.withLock { $0[path] = nil } }
}

/// A process runner that runs nothing: `npx` is found when `hasNode`; the
/// install writes `lines`, may "install" the skill on the file system, and
/// ends with `status`, or with `holds` runs until cancelled.
final class ScriptedRunner: ProcessRunner {
    let hasNode: Bool
    let lines: [String]
    let status: Int32
    let holds: Bool
    let installs: (@Sendable () -> Void)?
    let calls = Mutex<[[String]]>([])
    let holding = Mutex(false)

    init(hasNode: Bool = true, lines: [String] = [], status: Int32 = 0, holds: Bool = false, installs: (@Sendable () -> Void)? = nil) {
        self.hasNode = hasNode
        self.lines = lines
        self.status = status
        self.holds = holds
        self.installs = installs
    }

    func run(_ executable: String, arguments: [String], line: @escaping @Sendable (String) -> Void) async -> Int32 {
        calls.withLock { $0.append(arguments) }
        if arguments.last == "command -v npx" { return hasNode ? 0 : 1 }
        lines.forEach(line)
        if holds {
            holding.withLock { $0 = true }
            while !Task.isCancelled { try? await Task.sleep(for: .milliseconds(5)) }
            return 143
        }
        installs?()
        return status
    }
}

@Suite("Setup in the app")
struct SetupDeskTests {
    static let home = "/Users/me"
    static let bundle = URL(fileURLWithPath: "/Applications/Havooch.app")
    static let command = "/Applications/Havooch.app/Contents/Helpers/havooch"
    static let link = "/Users/me/.local/bin/havooch"
    static let claudeSkill = "/Users/me/.claude/skills/havooch-mate/SKILL.md"

    private func desk(_ items: [String: FileItem] = [:], runner: any ProcessRunner = ScriptedRunner(), failing: Set<String> = [])
        -> (SetupDesk, MemoryFileSystem)
    {
        let fileSystem = MemoryFileSystem([Self.command: .file].merging(items) { $1 }, failing: failing)
        let desk = SetupDesk(
            environment: ["HOME": Self.home, "SHELL": "/bin/zsh"], bundle: Self.bundle, fileSystem: fileSystem, runner: runner
        )
        return (desk, fileSystem)
    }

    @Test("it probes once at launch and again on asking, and reports each detection in state")
    func probes() {
        let (desk, _) = desk(["/Applications/Claude.app": .folder, Self.claudeSkill: .file])
        #expect(desk.probes == 1)
        desk.probe()
        #expect(desk.probes == 2)
        let setup = StateReport.Setup(desk, target: .video(fileName: "cut2.mp4"))
        #expect(setup.commandLine.detection == "notDetected")
        #expect(setup.commandLine.command == Self.command)
        let claude = setup.harnesses[0]
        #expect((claude.name, claude.presence, claude.skill) == ("Claude Code", "detected", "detected"))
        #expect(claude.prompt == "/havooch-mate listen for my feedback on cut2.mp4")
        #expect(setup.harnesses.map(\.prompt) == [
            "/havooch-mate listen for my feedback on cut2.mp4", "$havooch-mate listen for my feedback on cut2.mp4",
            "/havooch-mate listen for my feedback on cut2.mp4", "/skill:havooch-mate listen for my feedback on cut2.mp4",
            "Use the havooch-mate skill to listen for my feedback on cut2.mp4",
        ])
        // OpenCode reads Claude Code's skills folder too.
        #expect(setup.line == "setup: command line not detected; skill detected for Claude Code, OpenCode")
    }

    @Test("Link makes the link, and the report then says detected")
    func links() throws {
        let (desk, fileSystem) = desk()
        try desk.link()
        #expect(fileSystem[Self.link] == .link(to: Self.command))
        #expect(desk.report.commandLine.detection == .detected)
        #expect(desk.linkFailure == nil)
    }

    @Test("a failed Link keeps its ln -sf line for the view and refuses with it")
    func linkFails() {
        let (desk, _) = desk([Self.link: .file])
        #expect(throws: AppRefusal(
            "/Users/me/.local/bin/havooch is already there and isn't a link, so Havooch leaves it alone. Run this in a terminal: "
                + "mkdir -p ~/.local/bin && ln -sf /Applications/Havooch.app/Contents/Helpers/havooch ~/.local/bin/havooch"
        )) {
            try desk.link()
        }
        let setup = StateReport.Setup(desk, target: nil)
        #expect(setup.commandLine.fallback == "mkdir -p ~/.local/bin && ln -sf \(Self.command) ~/.local/bin/havooch")
        #expect(setup.commandLine.detection == "notDetected")
    }

    @Test("a build that isn't bundled has no command to link")
    func notBundled() {
        let desk = SetupDesk(
            environment: ["HOME": Self.home], bundle: URL(fileURLWithPath: "/build/debug"), fileSystem: MemoryFileSystem(),
            runner: ScriptedRunner()
        )
        #expect(desk.command == nil)
        #expect(throws: AppRefusal.self) { try desk.link() }
    }

    @Test("Install runs for the harnesses found without the skill, streams its log, and reads the disk again when done")
    func installs() async throws {
        let fileSystem = MemoryFileSystem()
        let runner = ScriptedRunner(lines: ["Installing havooch-mate", "Installed for Codex"]) {
            fileSystem.items.withLock { $0["/Users/me/.agents/skills/havooch-mate/SKILL.md"] = .file }
        }
        let desk = SetupDesk(
            environment: ["HOME": Self.home, "SHELL": "/bin/zsh"], bundle: Self.bundle, fileSystem: fileSystem, runner: runner
        )
        fileSystem.items.withLock { items in
            items["/Applications/Claude.app"] = .folder
            items[Self.claudeSkill] = .file
            items["/opt/homebrew/bin/codex"] = .file
        }
        let run = try desk.startInstall(for: [])
        #expect(run.state == .running)
        #expect(run.install.harnesses.map(\.installName) == ["codex"])
        await desk.installEnded()
        let install = try #require(desk.install)
        #expect(install.state == .done)
        #expect(install.exitStatus == 0)
        #expect(install.log == ["Installing havooch-mate", "Installed for Codex"])
        #expect(runner.calls.withLock { $0 }.last == ["-l", "-c", "exec env CI=true NO_COLOR=1 npx skills add \(HarnessCatalog.source) --skill havooch-mate -g -y -a codex"])
        #expect(desk.report.harnesses.first { $0.harness.installName == "codex" }?.skill == .detected)
        let report = StateReport.Install(install)
        #expect(report.state == "done")
    }

    @Test("Install for a harness named installs for it, whether found or not")
    func installNamed() throws {
        let (desk, _) = desk(runner: ScriptedRunner())
        #expect(try desk.plan(for: ["pi", "Claude Code"]).harnesses.map(\.installName) == ["claude-code", "pi"])
    }

    @Test("Install is refused for a harness Havooch doesn't know, and when there's nothing to install for", arguments: [
        ([String: FileItem](), ["gemini"], "no harness gemini; Havooch sets up claude-code, codex, cursor, pi and opencode"),
        ([:], [], "Havooch found no harness to install for; name one with --harness"),
        (["/Applications/Claude.app": .folder, "/Users/me/.claude/skills/havooch-mate/SKILL.md": .file], [],
         "the skill is detected for every harness found (Claude Code); name one with --harness to install it again"),
    ])
    func refused(items: [String: FileItem], names: [String], reason: String) {
        let (desk, _) = desk(items)
        #expect(throws: AppRefusal(reason)) { try desk.startInstall(for: names) }
        #expect(desk.install == nil)
    }

    @Test("a failed install ends failed with its exit status")
    func fails() async throws {
        let (desk, _) = desk(runner: ScriptedRunner(lines: ["npm error 404"], status: 1))
        try desk.startInstall(for: ["codex"])
        await desk.installEnded()
        #expect(desk.install?.state == .failed)
        #expect(desk.install?.exitStatus == 1)
    }

    @Test("without npx the install ends saying Node is necessary, and runs nothing")
    func noNode() async throws {
        let runner = ScriptedRunner(hasNode: false)
        let (desk, _) = desk(runner: runner)
        try desk.startInstall(for: ["codex"])
        await desk.installEnded()
        #expect(desk.install?.state == .noNode)
        #expect(desk.install?.log.last?.hasPrefix("Node is necessary") == true)
        #expect(runner.calls.withLock { $0 }.count == 1)
    }

    @Test("Cancel stops the running install; a second install is refused while one runs")
    func cancels() async throws {
        let runner = ScriptedRunner(lines: ["Installing havooch-mate"], holds: true)
        let (desk, _) = desk(runner: runner)
        try desk.startInstall(for: ["codex"])
        while !runner.holding.withLock({ $0 }) { try await Task.sleep(for: .milliseconds(5)) }
        #expect(throws: AppRefusal("an install is already running; havooch setup cancel stops it")) {
            try desk.startInstall(for: ["pi"])
        }
        let cancelled = try await desk.cancelInstall()
        #expect(cancelled.state == .cancelled)
        #expect(cancelled.log == ["Installing havooch-mate"])
        await #expect(throws: AppRefusal("no install is running")) { try await desk.cancelInstall() }
    }
}

extension StateReport {
    /// The install as `state --json` reports it.
    fileprivate typealias Install = Setup.Install
}

@Suite("Setup in state")
struct SetupStateTests {
    @Test("state --json carries setup, its prompts naming the open video's file")
    func stateCarriesSetup() throws {
        let support = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: support) }
        let setup = SetupDesk(
            environment: ["HOME": "/Users/me"], bundle: URL(fileURLWithPath: "/Applications/Havooch.app"),
            fileSystem: MemoryFileSystem(["/Users/me/.local/bin/havooch": .link(to: "/Applications/Havooch.app/Contents/Helpers/havooch"),
                                          "/Applications/Havooch.app/Contents/Helpers/havooch": .file]),
            runner: ScriptedRunner()
        )
        let model = AppModel(environment: [SupportFolder.overrideVariable: support.path], setup: setup).makeWindow()
        let state = model.state()
        #expect(state.setup?.commandLine.detection == "detected")
        #expect(state.setup?.harnesses.allSatisfy { $0.prompt == nil } == true)
        #expect(state.json.contains("\"setup\" : {"))
        #expect(state.lines.contains("setup: command line detected; skill not detected for any harness\n"))
    }
}
