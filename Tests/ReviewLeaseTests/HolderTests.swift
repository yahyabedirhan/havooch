import Foundation
import ReviewLease
import Testing

@Suite("Who sends a request")
struct HolderTests {
    /// A process table of the records given, read as the process `current`.
    struct FakeProcesses: ProcessTable {
        var currentPID: Int32
        var records: [ProcessRecord]

        func process(_ pid: Int32) -> ProcessRecord? {
            records.first { $0.pid == pid }
        }
    }

    static let folder = URL(fileURLWithPath: "/Users/me/shop", isDirectory: true)
    static let started = Date(timeIntervalSince1970: 1_700_000_000)

    /// `havooch` (300) run by zsh (200) run by `codex` (100).
    static let processes = FakeProcesses(currentPID: 300, records: [
        ProcessRecord(pid: 300, parent: 200, started: started, name: "havooch"),
        ProcessRecord(pid: 200, parent: 100, started: started, name: "-zsh"),
        ProcessRecord(pid: 100, parent: 1, started: started, name: "codex"),
    ])

    @Test("a Claude Code session is the holder, whatever shell runs the command")
    func session() {
        let holder = Holder.find(variables: ["CLAUDE_CODE_SESSION_ID": "abc"], workingDirectory: Self.folder, processes: Self.processes)
        #expect(holder == Holder(key: "CLAUDE_CODE_SESSION_ID=abc", name: "Claude Code", place: "/Users/me/shop"))
    }

    @Test("a Codex or Pi session is the holder, named for its harness", arguments: [
        ("CODEX_THREAD_ID", "019a-thread", "Codex"), ("PI_SESSION_ID", "pi-1", "Pi"),
    ])
    func harnessSession(variable: String, session: String, name: String) {
        let holder = Holder.find(variables: [variable: session], workingDirectory: Self.folder, processes: Self.processes)
        #expect(holder == Holder(key: "\(variable)=\(session)", name: name, place: "/Users/me/shop"))
    }

    @Test("an empty session variable counts as unset")
    func emptySession() {
        let holder = Holder.find(
            variables: ["CODEX_THREAD_ID": "", "PI_SESSION_ID": "pi-1"], workingDirectory: Self.folder, processes: Self.processes
        )
        #expect(holder.key == "PI_SESSION_ID=pi-1")
    }

    @Test("with two sessions set, the harness that runs the command is the holder: its process is the nearer ancestor")
    func nestedHarness() {
        let both = ["CLAUDE_CODE_SESSION_ID": "abc", "CODEX_THREAD_ID": "019a-thread"]
        // Codex run inside Claude Code: Codex's shell inherits Claude Code's session.
        let codexInClaude = FakeProcesses(currentPID: 300, records: [
            ProcessRecord(pid: 300, parent: 200, started: Self.started, name: "havooch"),
            ProcessRecord(pid: 200, parent: 100, started: Self.started, name: "zsh"),
            ProcessRecord(pid: 100, parent: 50, started: Self.started, name: "codex"),
            ProcessRecord(pid: 50, parent: 1, started: Self.started, name: "claude"),
        ])
        #expect(Holder.find(variables: both, workingDirectory: Self.folder, processes: codexInClaude).name == "Codex")
        let claudeInCodex = FakeProcesses(currentPID: 300, records: [
            ProcessRecord(pid: 300, parent: 200, started: Self.started, name: "havooch"),
            ProcessRecord(pid: 200, parent: 100, started: Self.started, name: "zsh"),
            ProcessRecord(pid: 100, parent: 50, started: Self.started, name: "claude"),
            ProcessRecord(pid: 50, parent: 1, started: Self.started, name: "codex"),
        ])
        #expect(Holder.find(variables: both, workingDirectory: Self.folder, processes: claudeInCodex).name == "Claude Code")
        // Neither harness among the ancestors: the first in the table.
        let neither = FakeProcesses(currentPID: 300, records: [])
        #expect(Holder.find(variables: both, workingDirectory: Self.folder, processes: neither).key == "CLAUDE_CODE_SESSION_ID=abc")
    }

    @Test("without a session, the nearest ancestor that isn't a shell is the holder")
    func ancestor() {
        let holder = Holder.find(variables: [:], workingDirectory: Self.folder, processes: Self.processes)
        #expect(holder == Holder(key: "process:100@1700000000000000", name: "codex", place: "/Users/me/shop"))
    }

    @Test("HAVOOCH_CONTROL_KEY replaces the key only, and a blank one counts as unset")
    func keyOverride() {
        let named = Holder.find(
            variables: ["CLAUDE_CODE_SESSION_ID": "abc", "HAVOOCH_CONTROL_KEY": "listener-1"],
            workingDirectory: Self.folder, processes: Self.processes
        )
        #expect(named == Holder(key: "listener-1", name: "Claude Code", place: "/Users/me/shop"))
        let blank = Holder.find(
            variables: ["CLAUDE_CODE_SESSION_ID": "abc", "HAVOOCH_CONTROL_KEY": "  "],
            workingDirectory: Self.folder, processes: Self.processes
        )
        #expect(blank.key == "CLAUDE_CODE_SESSION_ID=abc")
    }

    @Test("HAVOOCH_CONTROL_KEY replaces a Codex or Pi session's key too, and keeps its name", arguments: [
        ("CODEX_THREAD_ID", "Codex"), ("PI_SESSION_ID", "Pi"),
    ])
    func keyOverridesHarness(variable: String, name: String) {
        let holder = Holder.find(
            variables: [variable: "s-1", "HAVOOCH_CONTROL_KEY": "listener-1"], workingDirectory: Self.folder, processes: Self.processes
        )
        #expect(holder == Holder(key: "listener-1", name: name, place: "/Users/me/shop"))
    }

    @Test("a Herdr pane is the place when there is one")
    func place() {
        let holder = Holder.find(variables: ["HERDR_PANE_ID": "7"], workingDirectory: Self.folder, processes: Self.processes)
        #expect(holder.place == "Herdr pane 7")
    }

    @Test("a process table that can't be read gives an unknown holder")
    func unknown() {
        let holder = Holder.find(variables: [:], workingDirectory: Self.folder, processes: FakeProcesses(currentPID: 300, records: []))
        #expect(holder.key == "process:unknown")
    }
}
