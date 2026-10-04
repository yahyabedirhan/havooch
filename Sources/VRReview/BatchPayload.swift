import Foundation

/// The one JSON object `wait` prints: the batch, its video, the context
/// and each comment with its images as absolute paths to PNG files.
public struct BatchPayload: Codable, Equatable, Sendable {
    public struct BatchPart: Codable, Equatable, Sendable {
        public var id: String
        /// ISO 8601, in UTC.
        public var sentAt: String

        public init(id: String, sentAt: String) {
            self.id = id
            self.sentAt = sentAt
        }
    }

    public struct VideoPart: Codable, Equatable, Sendable {
        public var path: String
        public var contentHash: String
        public var duration: Double
        public var title: String

        public init(path: String, contentHash: String, duration: Double, title: String) {
            self.path = path
            self.contentHash = contentHash
            self.duration = duration
            self.title = title
        }
    }

    /// One timed line of the transcript, in seconds of the video.
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

    public struct CommentPart: Codable, Equatable, Sendable {
        public var id: String
        public var time: Double
        public var text: String
        public var keyframePath: String
        /// `{x, y, w, h}`, parts of the frame from 0 to 1; `null` for a
        /// comment on the whole frame, and `cropPath` with it.
        public var region: Region?
        public var cropPath: String?
        public var transcript: [Line]

        public init(
            id: String, time: Double, text: String, keyframePath: String, region: Region?, cropPath: String?, transcript: [Line]
        ) {
            self.id = id
            self.time = time
            self.text = text
            self.keyframePath = keyframePath
            self.region = region
            self.cropPath = cropPath
            self.transcript = transcript
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try container.encode(time, forKey: .time)
            try container.encode(text, forKey: .text)
            try container.encode(keyframePath, forKey: .keyframePath)
            // Written as `null`, never left out: a listener reads the same keys every time.
            try container.encode(region, forKey: .region)
            try container.encode(cropPath, forKey: .cropPath)
            try container.encode(transcript, forKey: .transcript)
        }
    }

    public var batch: BatchPart
    public var video: VideoPart
    /// The context's text, or `null` when the listener already has it.
    public var context: String?
    public var comments: [CommentPart]

    /// The payload of `batch` of `review`: its comments that aren't
    /// finished, in time order, which is all of them on the first delivery
    /// and the unfinished ones on a later one. `keyframe` and `crop` give
    /// each comment's image file; `crop` is asked only for a comment with
    /// a region.
    public static func make(
        batch: Batch, review: Review, context: String?, keyframe: (CommentID) -> String, crop: (CommentID) -> String
    ) -> BatchPayload {
        let listed = Set(batch.comments)
        let comments = review.comments.filter { listed.contains($0.id) && $0.state != .done && $0.state != .failed }
        return BatchPayload(
            batch: BatchPart(id: batch.id.rawValue, sentAt: batch.sentAt.formatted(.iso8601)),
            video: VideoPart(
                path: review.video.path, contentHash: review.video.contentHash, duration: review.video.duration,
                title: review.video.title
            ),
            context: context,
            comments: comments.map { comment in
                CommentPart(
                    id: comment.id.rawValue, time: comment.time, text: comment.text, keyframePath: keyframe(comment.id),
                    region: comment.region, cropPath: comment.region == nil ? nil : crop(comment.id),
                    transcript: batch.transcripts[comment.id] ?? []
                )
            }
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(batch, forKey: .batch)
        try container.encode(video, forKey: .video)
        try container.encode(context, forKey: .context)
        try container.encode(comments, forKey: .comments)
    }

    /// The payload as one JSON object: keys sorted, slashes as they are.
    public func encoded() -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        // Strings, numbers and lists of them: encoding can't fail.
        return try! encoder.encode(self)
    }
}
