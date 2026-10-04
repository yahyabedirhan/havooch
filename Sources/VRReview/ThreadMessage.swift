import Foundation

/// One message in a comment's thread: who wrote it, what kind it is, its
/// text and when it was written.
public struct ThreadMessage: Codable, Equatable, Sendable {
    public enum Author: String, Codable, Sendable {
        case person, agent
    }

    public enum Kind: String, Codable, Sendable {
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
