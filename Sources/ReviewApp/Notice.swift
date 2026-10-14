import Foundation
import ReviewCore

struct Notice: Equatable, Identifiable {
    enum Kind: Equatable {
        case acknowledgement
        case message
        case question
        case takeover
    }

    let id: UUID
    var thread: ThreadID
    var kind: Kind
    var agent: String
    var text: String
    var expires: Date

    static let life: TimeInterval = 5

    init(id: UUID = UUID(), thread: ThreadID, kind: Kind, agent: String, text: String, at now: Date) {
        self.id = id
        self.thread = thread
        self.kind = kind
        self.agent = agent
        self.text = text
        expires = now.addingTimeInterval(Self.life)
    }

    var knownAgent: KnownAgent? { KnownAgent(sender: agent) }

    var title: String {
        guard kind != .takeover else { return "New listener" }
        return "\(thread.number == 0 ? "General" : "#\(thread.number)") · \(agent)"
    }

    var hint: String? {
        kind == .question ? "Click to answer" : nil
    }
}
