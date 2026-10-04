import Foundation

/// The comments one send delivered together: everything that was queued on
/// one video at that moment. A listener gets a batch whole, from `wait`.
public struct Batch: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var sentAt: Date
    /// The batch's comments, in time order.
    public var commentIDs: [String]
    /// What the agent wrote about the batch as a whole, oldest first.
    public var thread: [ThreadMessage]

    public init(id: String, sentAt: Date, commentIDs: [String], thread: [ThreadMessage] = []) {
        self.id = id
        self.sentAt = sentAt
        self.commentIDs = commentIDs
        self.thread = thread
    }

    /// A batch kept before it had a thread has none.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        sentAt = try container.decode(Date.self, forKey: .sentAt)
        commentIDs = try container.decode([String].self, forKey: .commentIDs)
        thread = try container.decodeIfPresent([ThreadMessage].self, forKey: .thread) ?? []
    }
}
