import Foundation
import ReviewCore

/// A brief notice on the stage: the agent said something on a thread.
/// Every notice fades after a few seconds, a question too: the
/// question stays open on its thread, where the person answers it.
struct Notice: Equatable, Identifiable {
    enum Kind: Equatable {
        /// The agent has the send (`ack`).
        case acknowledgement
        /// The agent reports something (`reply`).
        case message
        /// The agent asks, and waits for the answer (`ask`).
        case question
        /// Another agent's `wait` replaced the listener that was there.
        /// On General, the notice says "Codex took over from Claude Code".
        case takeover
    }

    let id: UUID
    /// The thread the agent's words are on.
    var thread: ThreadID
    var kind: Kind
    /// The agent's name as people read it: `Claude Code`.
    var agent: String
    var text: String
    /// When the notice goes by itself.
    var expires: Date

    /// How long a notice is up, in seconds.
    static let life: TimeInterval = 5

    init(id: UUID = UUID(), thread: ThreadID, kind: Kind, agent: String, text: String, at now: Date) {
        self.id = id
        self.thread = thread
        self.kind = kind
        self.agent = agent
        self.text = text
        expires = now.addingTimeInterval(Self.life)
    }

    /// The agent harness its name says, for its logo; nil for a name no
    /// known agent has.
    var knownAgent: KnownAgent? { KnownAgent(sender: agent) }

    /// The notice's first line, which names the thread: `#3 · Claude
    /// Code`, or `General · Claude Code`. A takeover names no thread: it
    /// is about the listener, `New listener`.
    var title: String {
        guard kind != .takeover else { return "New listener" }
        return "\(thread.number == 0 ? "General" : "#\(thread.number)") · \(agent)"
    }

    /// What a click on the notice does, under its text.
    var hint: String? {
        kind == .question ? "Click to answer" : nil
    }
}
