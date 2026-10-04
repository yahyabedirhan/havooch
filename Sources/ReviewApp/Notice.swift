import Foundation
import ReviewCore

/// A brief notice on the stage: the agent said something. A message and an
/// acknowledgement go by themselves; a question stays until the person
/// clicks it or answers it, since the agent waits for it.
struct Notice: Equatable, Identifiable {
    /// What the agent's words are about.
    enum Subject: Equatable {
        case comment(ItemID)
        case batch(ItemID)
    }

    enum Kind: Equatable {
        /// The agent has the batch (`ack`).
        case acknowledgement
        /// The agent reports something (`reply`).
        case message
        /// The agent asks, and waits for the answer (`ask`).
        case question
    }

    let id: UUID
    var subject: Subject
    var kind: Kind
    /// The agent's name as people read it: `Claude Code`.
    var agent: String
    var text: String
    /// When the notice goes by itself; nil for one that stays.
    var expires: Date?

    /// How long a notice that goes by itself is up, in seconds.
    static let life: TimeInterval = 5

    init(id: UUID = UUID(), subject: Subject, kind: Kind, agent: String, text: String, at now: Date) {
        self.id = id
        self.subject = subject
        self.kind = kind
        self.agent = agent
        self.text = text
        expires = kind == .question ? nil : now.addingTimeInterval(Self.life)
    }

    /// The notice's first line. `number` is the comment's number in time
    /// order, as on its marker; nil for a batch, or a comment of a video
    /// that isn't the open one.
    func title(number: Int?) -> String {
        let comment = number.map { "comment \($0)" } ?? "a comment"
        switch (kind, subject) {
        case (.acknowledgement, _): return "\(agent) has your batch"
        case (.question, _): return "\(agent) asks about \(comment)"
        case (.message, .comment): return "\(agent) replied on \(comment)"
        case (.message, .batch): return "\(agent) on the whole batch"
        }
    }

    /// What a click on the notice does, under its text.
    var hint: String? {
        kind == .question ? "Click to answer" : nil
    }
}
