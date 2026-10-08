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
    /// The version on screen when the person sent, in a project's review:
    /// the payload's `video` and `project.onScreen`. Nil on a plain video.
    public let onScreen: VersionAnchor?

    public init(
        id: SendID, sentAt: Date, messageIDs: [MessageID], transcripts: [ThreadID: [SendPayload.Line]] = [:],
        onScreen: VersionAnchor? = nil
    ) {
        self.id = id
        self.sentAt = sentAt
        self.messageIDs = messageIDs
        self.transcripts = transcripts
        self.onScreen = onScreen
    }

    private enum CodingKeys: String, CodingKey {
        case id, sentAt, messageIDs, transcripts, onScreen
    }

    /// A send kept with no transcripts reads as one with no lines.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(SendID.self, forKey: .id)
        sentAt = try container.decode(Date.self, forKey: .sentAt)
        messageIDs = try container.decode([MessageID].self, forKey: .messageIDs)
        transcripts = try container.decodeIfPresent([ThreadID: [SendPayload.Line]].self, forKey: .transcripts) ?? [:]
        onScreen = try container.decodeIfPresent(VersionAnchor.self, forKey: .onScreen)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(sentAt, forKey: .sentAt)
        try container.encode(messageIDs, forKey: .messageIDs)
        try container.encode(transcripts, forKey: .transcripts)
        try container.encodeIfPresent(onScreen, forKey: .onScreen)
    }
}

/// A send as the outbox names it: its id, and the review it's on. On disk
/// a plain video's review is its `contentHash`, as builds before projects
/// wrote it, and a project's its `project` slug.
public struct SendRef: Codable, Hashable, Sendable {
    public var sendID: SendID
    public var review: ReviewKey

    public init(sendID: SendID, review: ReviewKey) {
        self.sendID = sendID
        self.review = review
    }

    /// A send of the plain video with `contentHash`.
    public init(sendID: SendID, contentHash: String) {
        self.init(sendID: sendID, review: .video(contentHash: contentHash))
    }

    private enum CodingKeys: String, CodingKey {
        case sendID, contentHash, project
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sendID = try container.decode(SendID.self, forKey: .sendID)
        if let slug = try container.decodeIfPresent(String.self, forKey: .project) {
            review = .project(slug: slug)
        } else {
            review = .video(contentHash: try container.decode(String.self, forKey: .contentHash))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sendID, forKey: .sendID)
        switch review {
        case .video(let contentHash): try container.encode(contentHash, forKey: .contentHash)
        case .project(let slug): try container.encode(slug, forKey: .project)
        }
    }
}
