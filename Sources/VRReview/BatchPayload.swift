import Foundation

/// What `wait` prints: one batch as the spec's JSON object, and nothing
/// more. Every key is always there; what's missing is `null`.
///
///     {"batch": {"id", "sentAt"},
///      "video": {"path", "contentHash", "duration", "title"},
///      "context": "…" or null,
///      "comments": [{"id", "time", "text", "keyframePath", "region",
///                    "cropPath", "transcript": [{"start", "end", "text"}]}]}
public struct BatchPayload: Codable, Equatable, Sendable {
    public struct Header: Codable, Equatable, Sendable {
        public var id: String
        /// ISO 8601, UTC.
        public var sentAt: String

        public init(id: String, sentAt: String) {
            self.id = id
            self.sentAt = sentAt
        }
    }

    /// One line of the transcript, with its times in seconds.
    public struct Line: Codable, Equatable, Sendable {
        public var start: Double
        public var end: Double
        public var text: String

        public init(start: Double, end: Double, text: String) {
            self.start = start
            self.end = end
            self.text = text
        }
    }

    public struct Item: Codable, Equatable, Sendable {
        public var id: String
        public var time: Double
        public var text: String
        /// The keyframe's absolute path; `null` when the frame couldn't be
        /// saved.
        public var keyframePath: String?
        public var region: Region?
        /// The crop's absolute path; `null` without a region.
        public var cropPath: String?
        /// The lines from 15 s before to 15 s after `time`.
        public var transcript: [Line]

        public init(
            id: String, time: Double, text: String, keyframePath: String?, region: Region?, cropPath: String?, transcript: [Line]
        ) {
            self.id = id
            self.time = time
            self.text = text
            self.keyframePath = keyframePath
            self.region = region
            self.cropPath = cropPath
            self.transcript = transcript
        }

        enum CodingKeys: String, CodingKey { case id, time, text, keyframePath, region, cropPath, transcript }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try container.encode(time, forKey: .time)
            try container.encode(text, forKey: .text)
            // Encoded also when nil: `null`, never left out.
            try container.encode(keyframePath, forKey: .keyframePath)
            try container.encode(region, forKey: .region)
            try container.encode(cropPath, forKey: .cropPath)
            try container.encode(transcript, forKey: .transcript)
        }
    }

    public var batch: Header
    public var video: VideoInfo
    /// The video's context, on the first batch of a listener session and
    /// when it changed; else `null`.
    public var context: String?
    public var comments: [Item]

    enum CodingKeys: String, CodingKey { case batch, video, context, comments }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(batch, forKey: .batch)
        try container.encode(video, forKey: .video)
        try container.encode(context, forKey: .context)
        try container.encode(comments, forKey: .comments)
    }

    /// The payload of `batch` of the review `session`: its comments that
    /// aren't done or failed, in time order, each with the paths of its
    /// images and its transcript lines as the caller finds them.
    public init(
        batch: Batch,
        session: ReviewSession,
        context: String?,
        keyframePath: (Comment) -> String?,
        cropPath: (Comment) -> String?,
        transcript: (Comment) -> [Line]
    ) {
        self.batch = Header(id: batch.id, sentAt: batch.sentAt.formatted(.iso8601))
        video = session.video
        self.context = context
        comments = session.comments
            .filter { $0.batchID == batch.id && !$0.state.isFinal }
            .map { comment in
                Item(
                    id: comment.id,
                    time: comment.time,
                    text: comment.text,
                    keyframePath: keyframePath(comment),
                    region: comment.region,
                    cropPath: comment.region == nil ? nil : cropPath(comment),
                    transcript: transcript(comment)
                )
            }
    }
}
