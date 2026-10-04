import Foundation
import Testing
import VRLease

/// The holder a command is sent as, worked out from the variables and the
/// process tree it runs in.
@Suite struct HolderTests {
    static let work = URL(fileURLWithPath: "/work/shop", isDirectory: true)

    /// A process table in memory: the `video-review` command is
    /// `currentPID`, and `processes` its ancestors.
    struct Processes: ProcessTable {
        var currentPID: Int32
        var processes: [ProcessRecord]

        func process(_ pid: Int32) -> ProcessRecord? {
            processes.first { $0.pid == pid }
        }

        /// `video-review` (500), run by `zsh` (400) under the agent
        /// `claude` (300), under `launchd` (1).
        static let agent = Processes(currentPID: 500, processes: [
            ProcessRecord(pid: 500, parent: 400, started: Date(timeIntervalSince1970: 1_000), name: "video-review"),
            ProcessRecord(pid: 400, parent: 300, started: Date(timeIntervalSince1970: 900), name: "zsh"),
            ProcessRecord(pid: 300, parent: 1, started: Date(timeIntervalSince1970: 800.25), name: "claude"),
            ProcessRecord(pid: 1, parent: 0, started: Date(timeIntervalSince1970: 0), name: "launchd"),
        ])
    }

    func holder(_ variables: [String: String] = [:], processes: Processes = .agent) -> Holder {
        Holder.find(variables: variables, workingDirectory: Self.work, processes: processes)
    }

    @Test func inAClaudeCodeSessionTheHolderIsThatSessionWhateverProcessRunsTheCommand() {
        let first = holder(["CLAUDE_CODE_SESSION_ID": "5f1c", "HOME": "/Users/agent"])
        let fromAnotherShell = holder(["CLAUDE_CODE_SESSION_ID": "5f1c"], processes: Processes(currentPID: 900, processes: [
            ProcessRecord(pid: 900, parent: 1, started: Date(timeIntervalSince1970: 50), name: "video-review"),
        ]))

        #expect(first == Holder(key: "CLAUDE_CODE_SESSION_ID=5f1c", name: "Claude Code", place: "/work/shop"))
        #expect(fromAnotherShell == first)
    }

    @Test func withoutASessionTheHolderIsTheNearestAncestorThatIsNotAShellByPidAndStartTime() {
        #expect(holder() == Holder(key: "process:300@800250000", name: "claude", place: "/work/shop"))
        // An empty session variable is no session.
        #expect(holder(["CLAUDE_CODE_SESSION_ID": ""]) == Holder(key: "process:300@800250000", name: "claude", place: "/work/shop"))
    }

    @Test func aLoginShellOrSeveralShellsBetweenTheCommandAndTheAgentArePassedOver() {
        let tree = Processes(currentPID: 900, processes: [
            ProcessRecord(pid: 900, parent: 800, started: Date(timeIntervalSince1970: 50), name: "video-review"),
            ProcessRecord(pid: 800, parent: 700, started: Date(timeIntervalSince1970: 40), name: "bash"),
            ProcessRecord(pid: 700, parent: 600, started: Date(timeIntervalSince1970: 30), name: "-zsh"),
            ProcessRecord(pid: 600, parent: 1, started: Date(timeIntervalSince1970: 20), name: "codex"),
        ])

        #expect(holder(processes: tree) == Holder(key: "process:600@20000000", name: "codex", place: "/work/shop"))
    }

    @Test func aPidReusedByAnotherProcessIsAnotherHolder() {
        var later = Processes.agent
        later.processes[2].started = Date(timeIntervalSince1970: 2_000)

        #expect(holder(processes: later).key == "process:300@2000000000")
        #expect(holder(processes: later).key != holder().key)
    }

    @Test func withNothingButShellsUpToLaunchdTheFarthestShellHoldsAndWithNoProcessToReadAnUnknownAgent() {
        let shells = Processes(currentPID: 900, processes: [
            ProcessRecord(pid: 900, parent: 800, started: Date(timeIntervalSince1970: 50), name: "video-review"),
            ProcessRecord(pid: 800, parent: 700, started: Date(timeIntervalSince1970: 40), name: "bash"),
            ProcessRecord(pid: 700, parent: 1, started: Date(timeIntervalSince1970: 30), name: "-zsh"),
        ])
        #expect(holder(processes: shells) == Holder(key: "process:700@30000000", name: "-zsh", place: "/work/shop"))

        let unreadable = Processes(currentPID: 900, processes: [])
        #expect(holder(processes: unreadable) == Holder(key: "process:unknown", name: "an unknown agent", place: "/work/shop"))
    }

    @Test func inAHerdrPaneThePlaceIsThePaneNeverPartOfTheKey() {
        #expect(holder(["HERDR_PANE_ID": "w1-2", "CLAUDE_CODE_SESSION_ID": "5f1c"])
            == Holder(key: "CLAUDE_CODE_SESSION_ID=5f1c", name: "Claude Code", place: "Herdr pane w1-2"))
        #expect(holder(["HERDR_PANE_ID": ""]).place == "/work/shop")
    }

    @Test func theKeyVariableNamesTheKeyOverTheSessionAndTheProcessAndTheNameAndPlaceStay() {
        #expect(holder(["VIDEO_REVIEW_CONTROL_KEY": "my-run", "CLAUDE_CODE_SESSION_ID": "5f1c"])
            == Holder(key: "my-run", name: "Claude Code", place: "/work/shop"))
        #expect(holder(["VIDEO_REVIEW_CONTROL_KEY": "my-run"]) == Holder(key: "my-run", name: "claude", place: "/work/shop"))
    }

    @Test(arguments: ["", "  ", "\t\n"])
    func anEmptyOrBlankKeyVariableIsNoKey(value: String) {
        #expect(holder(["VIDEO_REVIEW_CONTROL_KEY": value, "CLAUDE_CODE_SESSION_ID": "5f1c"])
            == Holder(key: "CLAUDE_CODE_SESSION_ID=5f1c", name: "Claude Code", place: "/work/shop"))
    }

    @Test func theSystemsProcessTableReadsThisProcessAndItsParent() throws {
        let table = SystemProcessTable()
        let this = try #require(table.process(table.currentPID))

        #expect(this.pid == getpid())
        #expect(this.parent == getppid())
        #expect(!this.name.isEmpty)
        #expect(this.started <= Date())
        #expect(table.process(this.parent)?.pid == this.parent)
    }
}
