import Foundation

/// One message in the thread of a comment or of a batch: who wrote it, what
/// it is, its text and when it was written. The agent writes messages and
/// questions; the person writes answers.
public struct ThreadMessage: Codable, Equatable, Sendable {
    public enum Author: String, Codable, Equatable, Sendable {
        case person, agent
    }

    public enum Kind: String, Codable, Equatable, Sendable {
        case message, question, answer
    }

    public var author: Author
    public var kind: Kind
    public var text: String
    public var at: Date

    public init(author: Author, kind: Kind, text: String, at: Date) {
        self.author = author
        self.kind = kind
        self.text = text
        self.at = at
    }
}
