import Foundation

/// The queue as one send took it: the comments that were queued then, in
/// time order, with the transcript lines around each as they existed at
/// the send.
public struct Batch: Codable, Equatable, Identifiable, Sendable {
    public var id: BatchID
    public var sentAt: Date
    public var comments: [CommentID]
    /// The messages about the batch as a whole.
    public var thread: [ThreadMessage]
    /// Captured at the send, so a later delivery needs neither the video
    /// open nor a transcriber running.
    public var transcripts: [CommentID: [BatchPayload.Line]]

    public init(
        id: BatchID, sentAt: Date, comments: [CommentID], thread: [ThreadMessage] = [],
        transcripts: [CommentID: [BatchPayload.Line]] = [:]
    ) {
        self.id = id
        self.sentAt = sentAt
        self.comments = comments
        self.thread = thread
        self.transcripts = transcripts
    }

    private enum CodingKeys: String, CodingKey {
        case id, sentAt, comments, thread, transcripts
    }

    /// As it is kept on disk: the transcripts are one object, each
    /// comment's id naming its lines.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(BatchID.self, forKey: .id)
        sentAt = try container.decode(Date.self, forKey: .sentAt)
        comments = try container.decode([CommentID].self, forKey: .comments)
        thread = try container.decode([ThreadMessage].self, forKey: .thread)
        let lines = try container.decode([String: [BatchPayload.Line]].self, forKey: .transcripts)
        transcripts = Dictionary(uniqueKeysWithValues: lines.map { (CommentID(rawValue: $0.key), $0.value) })
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(sentAt, forKey: .sentAt)
        try container.encode(comments, forKey: .comments)
        try container.encode(thread, forKey: .thread)
        try container.encode(
            Dictionary(uniqueKeysWithValues: transcripts.map { ($0.key.rawValue, $0.value) }), forKey: .transcripts
        )
    }
}
