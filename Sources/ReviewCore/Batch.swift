import Foundation

/// The comments one Cmd+Return sent together: what the listener takes and
/// answers as one.
public struct Batch: Codable, Equatable, Sendable, Identifiable {
    public let id: ItemID
    public let sentAt: Date
    /// The batch's comments, in time order.
    public let commentIDs: [ItemID]
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
