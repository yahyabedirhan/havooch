import Foundation

/// The person's messages one Cmd+Enter sent together: every queued message
/// of the video at that moment, on any threads. The listener takes and
/// acknowledges it as one.
public struct Send: Codable, Equatable, Sendable, Identifiable {
    public let id: SendID
    public let sentAt: Date
    /// The send's messages: threads in time order, General first, and the
    /// order written within a thread.
    public let messageIDs: [MessageID]

    public init(id: SendID, sentAt: Date, messageIDs: [MessageID]) {
        self.id = id
        self.sentAt = sentAt
        self.messageIDs = messageIDs
    }
}

/// A send as the outbox names it: its id, and the content hash of the video
/// it's about, since the outbox holds sends of every video.
public struct SendRef: Codable, Hashable, Sendable {
    public var sendID: SendID
    public var contentHash: String

    public init(sendID: SendID, contentHash: String) {
        self.sendID = sendID
        self.contentHash = contentHash
    }
}
