import Foundation

/// The comments one send delivered together: everything that was queued on
/// one video at that moment. A listener gets a batch whole, from `wait`.
public struct Batch: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var sentAt: Date
    /// The batch's comments, in time order.
    public var commentIDs: [String]

    public init(id: String, sentAt: Date, commentIDs: [String]) {
        self.id = id
        self.sentAt = sentAt
        self.commentIDs = commentIDs
    }
}
