import Foundation
import Testing
import VRLease

/// A process table of a few records, with the command as process 100.
private struct FakeProcesses: ProcessTable {
    var currentPID: Int32 = 100
    var records: [Int32: ProcessRecord]

    init(_ records: [ProcessRecord]) {
        self.records = Dictionary(uniqueKeysWithValues: records.map { ($0.pid, $0) })
    }

    func process(_ pid: Int32) -> ProcessRecord? { records[pid] }
}

private let started = Date(timeIntervalSince1970: 1_000)
private let folder = URL(fileURLWithPath: "/Users/me/repo", isDirectory: true)

/// The command (100) run by zsh (90), run by `claude` (80), run by a login shell (70).
private let agentTree = FakeProcesses([
    ProcessRecord(pid: 100, parent: 90, started: started, name: "video-review"),
    ProcessRecord(pid: 90, parent: 80, started: started, name: "zsh"),
    ProcessRecord(pid: 80, parent: 70, started: started, name: "claude"),
    ProcessRecord(pid: 70, parent: 1, started: started, name: "-zsh"),
])

@Suite struct HolderTests {
    @Test func aSessionVariableNamesTheHolderWhateverProcessRunsTheCommand() {
        let holder = Holder.find(
            variables: ["CLAUDE_CODE_SESSION_ID": "abc"], workingDirectory: folder, processes: agentTree
        )
        #expect(holder == Holder(key: "CLAUDE_CODE_SESSION_ID=abc", name: "Claude Code", place: "/Users/me/repo"))
    }

    @Test func withoutASessionTheHolderIsTheNearestAncestorThatIsNotAShell() {
        let holder = Holder.find(variables: [:], workingDirectory: folder, processes: agentTree)
        #expect(holder.key == "process:80@1000000000")
        #expect(holder.name == "claude")
    }

    @Test func whenEveryAncestorIsAShellTheHolderIsTheFarthestOne() {
        let shells = FakeProcesses([
            ProcessRecord(pid: 100, parent: 90, started: started, name: "video-review"),
            ProcessRecord(pid: 90, parent: 70, started: started, name: "bash"),
            ProcessRecord(pid: 70, parent: 1, started: started, name: "-zsh"),
        ])
        #expect(Holder.find(variables: [:], workingDirectory: folder, processes: shells).key == "process:70@1000000000")
    }

    @Test func aProcessTableThatCannotBeReadGivesAnUnknownHolder() {
        let holder = Holder.find(variables: [:], workingDirectory: folder, processes: FakeProcesses([]))
        #expect(holder.key == "process:unknown")
    }

    @Test func theKeyVariableReplacesTheKeyOnly() {
        let holder = Holder.find(
            variables: ["CLAUDE_CODE_SESSION_ID": "abc", "VIDEO_REVIEW_CONTROL_KEY": "run-7"],
            workingDirectory: folder, processes: agentTree
        )
        #expect(holder.key == "run-7")
        #expect(holder.name == "Claude Code")
    }

    @Test func aBlankKeyVariableCountsAsUnset() {
        let holder = Holder.find(
            variables: ["CLAUDE_CODE_SESSION_ID": "abc", "VIDEO_REVIEW_CONTROL_KEY": "  "],
            workingDirectory: folder, processes: agentTree
        )
        #expect(holder.key == "CLAUDE_CODE_SESSION_ID=abc")
    }

    @Test func aHerdrPaneIsThePlaceInsteadOfTheWorkingFolder() {
        let holder = Holder.find(
            variables: ["CLAUDE_CODE_SESSION_ID": "abc", "HERDR_PANE_ID": "w1:p2"],
            workingDirectory: folder, processes: agentTree
        )
        #expect(holder.place == "Herdr pane w1:p2")
    }
}
