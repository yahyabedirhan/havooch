import Foundation
import ReviewCore

/// A brief notice on the stage: the agent said something on a thread. A
/// message and an acknowledgement go by themselves; a question stays until
/// the person clicks it or answers it, since the agent waits for it.
struct Notice: Equatable, Identifiable {
    enum Kind: Equatable {
        /// The agent has the send (`ack`).
        case acknowledgement
        /// The agent reports something (`reply`).
        case message
        /// The agent asks, and waits for the answer (`ask`).
        case question
    }

    let id: UUID
    /// The thread the agent's words are on.
    var thread: ThreadID
    var kind: Kind
    /// The agent's name as people read it: `Claude Code`.
    var agent: String
    var text: String
    /// When the notice goes by itself; nil for one that stays.
    var expires: Date?

    /// How long a notice that goes by itself is up, in seconds.
    static let life: TimeInterval = 5

    init(id: UUID = UUID(), thread: ThreadID, kind: Kind, agent: String, text: String, at now: Date) {
        self.id = id
        self.thread = thread
        self.kind = kind
        self.agent = agent
        self.text = text
        expires = kind == .question ? nil : now.addingTimeInterval(Self.life)
    }

    /// The notice's first line, which names the thread: `#3 · Claude
    /// Code`, or `General · Claude Code`.
    var title: String {
        "\(thread.number == 0 ? "General" : "#\(thread.number)") · \(agent)"
    }

    /// What a click on the notice does, under its text.
    var hint: String? {
        kind == .question ? "Click to answer" : nil
    }
}
