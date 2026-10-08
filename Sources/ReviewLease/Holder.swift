import Foundation

/// Who sends a control request: the agent the lease is held by or refused
/// to. Every request carries one, worked out by the `havooch` command
/// on each call (`Holder.find`), so agents usually pass nothing.
public struct Holder: Codable, Hashable, Sendable {
    /// What tells one agent from another across its commands: the key it
    /// exports (`HAVOOCH_CONTROL_KEY`), else its session
    /// (`CLAUDE_CODE_SESSION_ID=…`, `CODEX_THREAD_ID=…`, `PI_SESSION_ID=…`),
    /// else its process (`process:<pid>@<start>`).
    public var key: String
    /// The agent's name as people read it: `Claude Code`, `Codex` or `Pi`
    /// from its session, else its process's name (`cursor-agent`). The app
    /// shows the logo of the harness this name says.
    public var name: String
    /// Where it runs: `Herdr pane <id>`, else its working folder.
    public var place: String

    public init(key: String, name: String, place: String) {
        self.key = key
        self.name = name
        self.place = place
    }

    /// An agent that exports its session id in one of these variables is
    /// that session, whatever subshell runs the command. `processes` are the
    /// names its harness runs as, which settle which session runs the
    /// command when one harness runs inside another and both are set.
    public static let sessionVariables: [(variable: String, agent: String, processes: Set<String>)] = [
        ("CLAUDE_CODE_SESSION_ID", "Claude Code", ["claude"]),
        ("CODEX_THREAD_ID", "Codex", ["codex"]),
        ("PI_SESSION_ID", "Pi", ["pi"]),
    ]

    /// The shells a command runs through, which never identify an agent:
    /// the holder is the nearest ancestor that isn't one.
    static let shells: Set<String> = ["sh", "bash", "zsh", "fish", "dash", "ksh", "mksh", "tcsh", "csh", "nu"]

    /// The variable that names the holder's key for every command run with
    /// it, for a setup where neither the agent's session nor its process
    /// stays the same across its commands. A value that's empty or blank
    /// counts as unset.
    public static let keyVariable = "HAVOOCH_CONTROL_KEY"

    /// The holder of a command run with `variables` in `workingDirectory`:
    /// the known session variable that's set (with more than one set, the
    /// one whose harness is the nearest ancestor, else the first in
    /// `sessionVariables`), else the nearest
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
        let sessions = sessionVariables.filter { !(variables[$0.variable] ?? "").isEmpty }
        if let first = sessions.first {
            let session = sessions.count == 1 ? first : nearestHarness(of: sessions, processes) ?? first
            return Holder(key: "\(session.variable)=\(variables[session.variable]!)", name: session.agent, place: place)
        }
        guard let agent = ancestor(processes) else {
            return Holder(key: "process:unknown", name: "an unknown agent", place: place)
        }
        let started = Int64((agent.started.timeIntervalSince1970 * 1_000_000).rounded())
        return Holder(key: "process:\(agent.pid)@\(started)", name: agent.name, place: place)
    }

    /// Of `sessions`, the one whose harness runs as the nearest ancestor of
    /// `processes.currentPID`; nil when none of them is found.
    private static func nearestHarness(
        of sessions: [(variable: String, agent: String, processes: Set<String>)], _ processes: any ProcessTable
    ) -> (variable: String, agent: String, processes: Set<String>)? {
        var pid = processes.process(processes.currentPID)?.parent ?? 1
        for _ in 0..<64 where pid > 1 {
            guard let process = processes.process(pid) else { return nil }
            if let session = sessions.first(where: { $0.processes.contains(process.name) }) { return session }
            pid = process.parent
        }
        return nil
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
