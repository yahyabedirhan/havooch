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
    /// Each thread's transcript window, cut when the send was made and
    /// kept, so a delivery again gives the same lines and needs no
    /// transcriber. General has none.
    public let transcripts: [ThreadID: [SendPayload.Line]]

    public init(id: SendID, sentAt: Date, messageIDs: [MessageID], transcripts: [ThreadID: [SendPayload.Line]] = [:]) {
        self.id = id
        self.sentAt = sentAt
        self.messageIDs = messageIDs
        self.transcripts = transcripts
    }

    private enum CodingKeys: String, CodingKey {
        case id, sentAt, messageIDs, transcripts
    }

    /// A send kept with no transcripts reads as one with no lines.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(SendID.self, forKey: .id)
        sentAt = try container.decode(Date.self, forKey: .sentAt)
        messageIDs = try container.decode([MessageID].self, forKey: .messageIDs)
        transcripts = try container.decodeIfPresent([ThreadID: [SendPayload.Line]].self, forKey: .transcripts) ?? [:]
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
