import Foundation

/// One message on a thread: who wrote it, what kind it is, its words and
/// when it was written. A person's message of the kind `message` is a work
/// item: it has a state, may point at a region of the keyframe, and names
/// the send it went out in. Its crop is a file named after its id, so the
/// message holds no path.
public struct Message: Codable, Equatable, Sendable, Identifiable {
    /// Who wrote a message.
    public enum Author: String, Codable, Sendable, CaseIterable {
        /// The person, in the app, or an operator through the CLI.
        case person
        /// The listener, with `ack`, `reply` or `ask`.
        case agent
    }

    /// What a message is.
    public enum Kind: String, Codable, Sendable, CaseIterable {
        /// Feedback by the person, or a reply by the agent.
        case message
        /// The agent's question; open until an answer follows it.
        case question
        /// The person's answer to the open question. It goes at once and
        /// never into the queue.
        case answer
    }

    public let id: MessageID
    public let author: Author
    public let kind: Kind
    public internal(set) var text: String
    public let at: Date
    /// The part of the keyframe a person's message points at; nil for the
    /// whole frame, and for every other message.
    public let region: Region?
    /// The state of a person's message of the kind `message`; nil for
    /// every other message.
    public internal(set) var state: MessageState?
    /// The send a person's message went out in; nil while it's queued.
    public internal(set) var sendID: SendID?

    public init(
        id: MessageID, author: Author, kind: Kind, text: String, at: Date,
        region: Region? = nil, state: MessageState? = nil, sendID: SendID? = nil
    ) {
        self.id = id
        self.author = author
        self.kind = kind
        self.text = text
        self.at = at
        self.region = region
        self.state = state
        self.sendID = sendID
    }

    /// Whether the message is a work item: a person's `message`.
    public var isWork: Bool {
        author == .person && kind == .message
    }
}
