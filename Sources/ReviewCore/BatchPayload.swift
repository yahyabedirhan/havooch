import Foundation

/// What `video-review wait` prints: one batch as the listener reads it, in
/// the shape the spec fixes for every prototype. A key with no value is
/// `null`, never left out.
///
///     { "batch":    { "id": "b-5d0c2a91", "sentAt": "2026-10-04T19:02:11Z" },
///       "video":    { "path": "/abs/sample.mp4", "contentHash": "…", "duration": 21.233, "title": "sample" },
///       "context":  null,
///       "comments": [ { "id": "c-7f3a9c2e", "time": 10, "text": "…", "keyframePath": "/abs/….png",
///                       "region": null, "cropPath": null, "transcript": [] } ] }
public struct BatchPayload: Codable, Equatable, Sendable {
    public struct BatchPart: Codable, Equatable, Sendable {
        public var id: ItemID
        public var sentAt: Date
    }

    public struct VideoPart: Codable, Equatable, Sendable {
        /// Where the file was when it was last opened.
        public var path: String
        public var contentHash: String
        /// The length in seconds, to the millisecond.
        public var duration: Double
        public var title: String
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

    /// A comment's PNG files, as absolute paths.
    public struct Images: Equatable, Sendable {
        public var keyframe: String
        /// The region's crop; nil for a comment on the whole frame.
        public var crop: String?

        public init(keyframe: String, crop: String?) {
            self.keyframe = keyframe
            self.crop = crop
        }
    }

    public struct CommentPart: Codable, Equatable, Sendable {
        public var id: ItemID
        public var time: Double
        public var text: String
        /// The PNG of the frame at `time`, as an absolute path.
        public var keyframePath: String
        /// The part of the frame the comment points at; `null` for the
        /// whole frame.
        public var region: Region?
        /// The PNG of the region, as an absolute path; `null` with no region.
        public var cropPath: String?
        /// The timed lines from 15 s before to 15 s after `time`.
        public var transcript: [Line]

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try container.encode(time, forKey: .time)
            try container.encode(text, forKey: .text)
            try container.encode(keyframePath, forKey: .keyframePath)
            try container.encode(region, forKey: .region)
            try container.encode(cropPath, forKey: .cropPath)
            try container.encode(transcript, forKey: .transcript)
        }
    }

    public var batch: BatchPart
    public var video: VideoPart
    /// The video's context text; `null` when this listener session already
    /// has it unchanged, or when there is none.
    public var context: String?
    public var comments: [CommentPart]

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(batch, forKey: .batch)
        try container.encode(video, forKey: .video)
        try container.encode(context, forKey: .context)
        try container.encode(comments, forKey: .comments)
    }

    /// The payload of `batch` of `review`, with `context` when it's due.
    /// It carries the batch's comments that aren't finished, in time order:
    /// all of them the first time, and only what's left when the batch is
    /// delivered again. `transcript` gives a comment its lines and `images`
    /// its PNG paths, so this module reads neither transcripts nor the store.
    public static func assemble(
        review: VideoReview, batch: Batch, context: String?,
        transcript: (Comment) -> [Line], images: (Comment) -> Images
    ) -> BatchPayload {
        BatchPayload(
            batch: BatchPart(id: batch.id, sentAt: batch.sentAt),
            video: VideoPart(
                path: review.video.path, contentHash: review.video.contentHash,
                duration: (review.video.duration * 1000).rounded() / 1000, title: review.video.title
            ),
            context: context,
            comments: review.comments(of: batch.id).filter { !$0.state.isFinal }.map { comment in
                let files = images(comment)
                return CommentPart(
                    id: comment.id, time: comment.time, text: comment.text, keyframePath: files.keyframe,
                    region: comment.region, cropPath: files.crop, transcript: transcript(comment)
                )
            }
        )
    }

    /// The payload as the JSON `wait` prints: readable, keys in order, the
    /// time as ISO 8601.
    public var json: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        // Strings, numbers and booleans: encoding can't fail.
        return String(decoding: try! encoder.encode(self), as: UTF8.self) + "\n"
    }
}
