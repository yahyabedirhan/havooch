import Foundation

/// What `video-review wait` prints: one send as the listener reads it. A
/// key with no value is `null`, never left out.
///
/// NOTE: This is the interim, flat shape of the thread model: one entry per
/// message, with its thread. The spec's payload, grouped by thread with
/// `history[]` and the transcript cut at send time, replaces it.
///
///     { "send":     { "id": "s-f92cbb2a-1", "sentAt": "2026-10-05T19:02:11Z" },
///       "video":    { "path": "/abs/sample.mp4", "contentHash": "…", "duration": 21.233, "title": "sample" },
///       "context":  null,
///       "messages": [ { "id": "m-f92cbb2a-1", "threadId": "t-f92cbb2a-1", "threadNumber": 1, "time": 10.01,
///                       "text": "…", "keyframePath": "/abs/….png", "region": null, "cropPath": null,
///                       "transcript": [] } ] }
public struct SendPayload: Codable, Equatable, Sendable {
    public struct SendPart: Codable, Equatable, Sendable {
        public var id: SendID
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

    /// A message's PNG files, as absolute paths.
    public struct Images: Equatable, Sendable {
        /// The thread's keyframe; nil on General.
        public var keyframe: String?
        /// The region's crop; nil for a message on the whole frame.
        public var crop: String?

        public init(keyframe: String?, crop: String?) {
            self.keyframe = keyframe
            self.crop = crop
        }
    }

    public struct MessagePart: Codable, Equatable, Sendable {
        public var id: MessageID
        public var threadId: ThreadID
        public var threadNumber: Int
        /// The thread's frame time; `null` on General.
        public var time: Double?
        public var text: String
        /// The thread's keyframe PNG, as an absolute path; `null` on General.
        public var keyframePath: String?
        /// The part of the frame the message points at; `null` for the
        /// whole frame.
        public var region: Region?
        /// The PNG of the region, as an absolute path; `null` with no region.
        public var cropPath: String?
        /// The timed lines from 15 s before to 15 s after `time`.
        public var transcript: [Line]

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try container.encode(threadId, forKey: .threadId)
            try container.encode(threadNumber, forKey: .threadNumber)
            try container.encode(time, forKey: .time)
            try container.encode(text, forKey: .text)
            try container.encode(keyframePath, forKey: .keyframePath)
            try container.encode(region, forKey: .region)
            try container.encode(cropPath, forKey: .cropPath)
            try container.encode(transcript, forKey: .transcript)
        }
    }

    public var send: SendPart
    public var video: VideoPart
    /// The video's context text; `null` when this listener session already
    /// has it unchanged, or when there is none.
    public var context: String?
    public var messages: [MessagePart]

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(send, forKey: .send)
        try container.encode(video, forKey: .video)
        try container.encode(context, forKey: .context)
        try container.encode(messages, forKey: .messages)
    }

    /// The payload of `send` of `review`, with `context` when it's due. It
    /// carries the send's messages that aren't finished: all of them the
    /// first time, and only what's left when the send is delivered again.
    /// `transcript` gives a thread its lines and `images` a message its PNG
    /// paths, so this module reads neither transcripts nor the store.
    public static func assemble(
        review: VideoReview, send: Send, context: String?,
        transcript: (ReviewThread) -> [Line], images: (Message, ReviewThread) -> Images
    ) -> SendPayload {
        let parts = review.threads.flatMap { thread in
            let lines = thread.time == nil ? [] : transcript(thread)
            return thread.messages.filter { $0.sendID == send.id && $0.state?.isFinal == false }.map { message in
                let files = images(message, thread)
                return MessagePart(
                    id: message.id, threadId: thread.id, threadNumber: thread.number, time: thread.time,
                    text: message.text, keyframePath: files.keyframe, region: message.region, cropPath: files.crop,
                    transcript: lines
                )
            }
        }
        return SendPayload(
            send: SendPart(id: send.id, sentAt: send.sentAt),
            video: VideoPart(
                path: review.video.path, contentHash: review.video.contentHash,
                duration: (review.video.duration * 1000).rounded() / 1000, title: review.video.title
            ),
            context: context,
            messages: parts
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
