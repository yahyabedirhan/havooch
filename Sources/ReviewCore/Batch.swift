import Foundation

/// The comments one Cmd+Return sent together: what the listener takes and
/// answers as one.
public struct Batch: Codable, Equatable, Sendable, Identifiable {
    public let id: ItemID
    public let sentAt: Date
    /// The batch's comments, in time order.
    public let commentIDs: [ItemID]
    /// What the agent said about the batch as one: its acknowledgement's
    /// words, and each reply to the batch's id.
    public internal(set) var messages: [ThreadMessage] = []
}

extension Batch {
    /// A batch written before it had messages reads with none.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(ItemID.self, forKey: .id)
        sentAt = try container.decode(Date.self, forKey: .sentAt)
        commentIDs = try container.decode([ItemID].self, forKey: .commentIDs)
        messages = try container.decodeIfPresent([ThreadMessage].self, forKey: .messages) ?? []
    }
}

/// A batch as the outbox names it: its id, and the content hash of the
/// video it's about, since the outbox holds batches of every video.
public struct BatchRef: Codable, Hashable, Sendable {
    public var batchID: ItemID
    public var contentHash: String

    public init(batchID: ItemID, contentHash: String) {
        self.batchID = batchID
        self.contentHash = contentHash
    }
}
