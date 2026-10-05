import Foundation

/// One message in a comment's thread, or one of a batch's own messages: who
/// wrote it, what kind it is, its words and when it was written.
public struct ThreadMessage: Codable, Equatable, Sendable, Identifiable {
    /// Who wrote a message.
    public enum Author: String, Codable, Sendable, CaseIterable {
        /// The person, in the answer box, or an operator with `thread answer`.
        case person
        /// The listener, with `ack`, `reply` or `ask`.
        case agent
    }

    /// What a message is.
    public enum Kind: String, Codable, Sendable, CaseIterable {
        /// Something the agent reports: a result, or its acknowledgement.
        case message
        /// Something the agent asks; open until an answer follows it.
        case question
        /// What the person answers to the open question.
        case answer
    }

    public let id: ItemID
    public let author: Author
    public let kind: Kind
    public let text: String
    public let at: Date

    public init(id: ItemID, author: Author, kind: Kind, text: String, at: Date) {
        self.id = id
        self.author = author
        self.kind = kind
        self.text = text
        self.at = at
    }
}

extension [ThreadMessage] {
    /// The question that waits for an answer: the last question, while no
    /// answer follows it. A thread has one at most.
    public var openQuestion: ThreadMessage? {
        guard let index = lastIndex(where: { $0.kind == .question }),
              !self[index...].contains(where: { $0.kind == .answer })
        else { return nil }
        return self[index]
    }
}
