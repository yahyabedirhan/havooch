import Darwin
import Foundation

/// Who sends a control request: the agent the lease is held by or refused
/// to. Every request carries one, worked out by the `video-review` command
/// on each call (`Holder.find`), so agents usually pass nothing.
public struct Holder: Codable, Hashable, Sendable {
    /// What tells one agent from another across its commands: the key it
    /// exports (`VIDEO_REVIEW_CONTROL_KEY`), else its session
    /// (`CLAUDE_CODE_SESSION_ID=…`), else its process (`process:<pid>@<start>`).
    public var key: String
    /// The agent's name as people read it: `Claude Code`, or its process's
    /// name (`codex`).
    public var name: String
    /// Where it runs: `Herdr pane <id>`, else its working folder.
    public var place: String

    public init(key: String, name: String, place: String) {
        self.key = key
        self.name = name
        self.place = place
    }

    /// An agent that exports its session id in one of these variables is
    /// that session, whatever subshell runs the command.
    public static let sessionVariables: [(variable: String, agent: String)] = [
        ("CLAUDE_CODE_SESSION_ID", "Claude Code"),
    ]

    /// The shells a command runs through, which never identify an agent:
    /// the holder is the nearest ancestor that isn't one.
    static let shells: Set<String> = ["sh", "bash", "zsh", "fish", "dash", "ksh", "mksh", "tcsh", "csh", "nu"]

    /// The variable that names the holder's key for every command run with
    /// it, for a setup where neither the agent's session nor its process
    /// stays the same across its commands. A value that's empty or blank
    /// counts as unset.
    public static let keyVariable = "VIDEO_REVIEW_CONTROL_KEY"

    /// The holder of a command run with `variables` in `workingDirectory`:
    /// the first known session variable that's set, else the nearest
    /// ancestor of this process that isn't a shell, as its pid and start
    /// time, read from `processes`. When even this process can't be read,
    /// `process:unknown`. `keyVariable`, when set, replaces the key only.
    public static func find(variables: [String: String], workingDirectory: URL, processes: any ProcessTable) -> Holder {
        let place = variables["HERDR_PANE_ID"].flatMap { $0.isEmpty ? nil : "Herdr pane \($0)" } ?? workingDirectory.path
        var holder = automatic(variables: variables, place: place, processes: processes)
        if let key = variables[keyVariable], !key.allSatisfy(\.isWhitespace) {
            holder.key = key
        }
        return holder
    }

    /// The holder its session, else its process, makes it.
    private static func automatic(variables: [String: String], place: String, processes: any ProcessTable) -> Holder {
        for (variable, agent) in sessionVariables {
            if let session = variables[variable], !session.isEmpty {
                return Holder(key: "\(variable)=\(session)", name: agent, place: place)
            }
        }
        guard let agent = ancestor(processes) else {
            return Holder(key: "process:unknown", name: "an unknown agent", place: place)
        }
        let started = Int64((agent.started.timeIntervalSince1970 * 1_000_000).rounded())
        return Holder(key: "process:\(agent.pid)@\(started)", name: agent.name, place: place)
    }

    /// The nearest ancestor of `processes.currentPID` that isn't a shell;
    /// the farthest shell when every readable ancestor up to launchd is one.
    private static func ancestor(_ processes: any ProcessTable) -> ProcessRecord? {
        guard var pid = processes.process(processes.currentPID)?.parent else { return nil }
        var farthest: ProcessRecord?
        // A process table is a tree, but never trust it not to loop.
        for _ in 0..<64 where pid > 1 {
            guard let process = processes.process(pid) else { break }
            let name = process.name.hasPrefix("-") ? String(process.name.dropFirst()) : process.name
            if !shells.contains(name) { return process }
            farthest = process
            pid = process.parent
        }
        return farthest
    }
}

/// One process as the process table has it.
public struct ProcessRecord: Equatable, Sendable {
    public var pid: Int32
    public var parent: Int32
    /// When it started: with the pid, it names the process even once the
    /// pid is reused.
    public var started: Date
    /// Its command's name (`zsh`, a login shell's `-zsh`, `claude`).
    public var name: String

    public init(pid: Int32, parent: Int32, started: Date, name: String) {
        self.pid = pid
        self.parent = parent
        self.started = started
        self.name = name
    }
}

/// The processes `Holder.find` walks up through: macOS's process table in
/// production, a fake in tests.
public protocol ProcessTable: Sendable {
    /// This process: the `video-review` command.
    var currentPID: Int32 { get }
    /// The process `pid`, or nil when there's none (or it can't be read).
    func process(_ pid: Int32) -> ProcessRecord?
}

/// The system's process table, through `sysctl`.
public struct SystemProcessTable: ProcessTable {
    public init() {}

    public var currentPID: Int32 { getpid() }

    public func process(_ pid: Int32) -> ProcessRecord? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var name: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        // A pid nobody has is no error: the answer is just empty.
        guard sysctl(&name, u_int(name.count), &info, &size, nil, 0) == 0, size > 0 else { return nil }
        let start = info.kp_proc.p_un.__p_starttime
        let command = withUnsafeBytes(of: info.kp_proc.p_comm) { bytes in
            String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
        }
        return ProcessRecord(
            pid: pid,
            parent: info.kp_eproc.e_ppid,
            started: Date(timeIntervalSince1970: TimeInterval(start.tv_sec) + TimeInterval(start.tv_usec) / 1_000_000),
            name: command
        )
    }
}
