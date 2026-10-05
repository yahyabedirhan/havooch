import Foundation

/// What `havooch wait` prints: one send as the listener reads it,
/// grouped by thread. Each thread carries its keyframe, its transcript
/// window as the send cut it, the conversation so far (`history`) and the
/// person's messages of this send. A key with no value is `null`, never
/// left out.
///
///     { "send":    { "id": "s-f92cbb2a-2", "sentAt": "2026-10-05T19:02:11Z" },
///       "video":   { "path": "/abs/sample.mp4", "contentHash": "…", "duration": 21.233, "title": "sample.mp4" },
///       "context": null,
///       "threads": [ { "id": "t-f92cbb2a-1", "number": 1, "time": 10.017, "keyframePath": "/abs/….png",
///                      "transcript": [ { "start": 6.067, "end": 14.333, "text": "…" } ],
///                      "history":  [ { "id": "m-f92cbb2a-1", "author": "person", "kind": "message", "text": "…",
///                                      "region": null, "cropPath": null } ],
///                      "messages": [ { "id": "m-f92cbb2a-9", "text": "…", "region": null, "cropPath": null } ] } ] }
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
        /// The file's name with its extension.
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

    /// The PNG files of a review, as absolute paths: the keyframe of a
    /// thread (nil on General) and the crop of a message (nil with no
    /// region). The caller knows where the store keeps them.
    public struct Images {
        public var keyframe: (ReviewThread) -> String?
        public var crop: (Message) -> String?

        public init(keyframe: @escaping (ReviewThread) -> String?, crop: @escaping (Message) -> String?) {
            self.keyframe = keyframe
            self.crop = crop
        }
    }

    /// An earlier message of a thread: the person's or the agent's.
    public struct HistoryPart: Codable, Equatable, Sendable {
        public var id: MessageID
        public var author: Message.Author
        public var kind: Message.Kind
        public var text: String
        public var region: Region?
        public var cropPath: String?

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try container.encode(author, forKey: .author)
            try container.encode(kind, forKey: .kind)
            try container.encode(text, forKey: .text)
            try container.encode(region, forKey: .region)
            try container.encode(cropPath, forKey: .cropPath)
        }
    }

    /// A person's message of this send: the work the listener does.
    public struct MessagePart: Codable, Equatable, Sendable {
        public var id: MessageID
        public var text: String
        /// The part of the frame the message points at; `null` for the
        /// whole frame.
        public var region: Region?
        /// The PNG of the region, as an absolute path; `null` with no region.
        public var cropPath: String?

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try container.encode(text, forKey: .text)
            try container.encode(region, forKey: .region)
            try container.encode(cropPath, forKey: .cropPath)
        }
    }

    /// One thread of the send, with all the listener needs to work on it.
    public struct ThreadPart: Codable, Equatable, Sendable {
        public var id: ThreadID
        public var number: Int
        /// The thread's frame time; `null` on General.
        public var time: Double?
        /// The thread's keyframe PNG, as an absolute path; `null` on General.
        public var keyframePath: String?
        /// The timed lines from 15 s before to 15 s after `time`, as the
        /// send cut them. Empty on General.
        public var transcript: [Line]
        /// The thread's earlier messages, in the order written.
        public var history: [HistoryPart]
        /// The person's messages of this send on the thread.
        public var messages: [MessagePart]

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try container.encode(number, forKey: .number)
            try container.encode(time, forKey: .time)
            try container.encode(keyframePath, forKey: .keyframePath)
            try container.encode(transcript, forKey: .transcript)
            try container.encode(history, forKey: .history)
            try container.encode(messages, forKey: .messages)
        }
    }

    public var send: SendPart
    public var video: VideoPart
    /// The video's context text; `null` when this listener session already
    /// has it unchanged, or when there is none.
    public var context: String?
    /// General first, then the threads in time order.
    public var threads: [ThreadPart]

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(send, forKey: .send)
        try container.encode(video, forKey: .video)
        try container.encode(context, forKey: .context)
        try container.encode(threads, forKey: .threads)
    }

    /// The payload of `send` of `review`, with `context` when it's due. It
    /// has one entry for each thread with a message of the send that isn't
    /// finished: all of them the first time, and only what's left when the
    /// send is delivered again. A thread's `history` is each of its
    /// messages that isn't in the entry's `messages` and isn't queued, so a
    /// delivery again also carries the agent's replies so far. `images`
    /// gives the PNG paths, so this module doesn't read the store.
    public static func assemble(review: VideoReview, send: Send, context: String?, images: Images) -> SendPayload {
        let threads = review.threads.compactMap { thread -> ThreadPart? in
            let work = thread.messages.filter { $0.sendID == send.id && $0.state?.isFinal == false }
            guard !work.isEmpty else { return nil }
            let now = Set(work.map(\.id))
            return ThreadPart(
                id: thread.id, number: thread.number, time: thread.time,
                keyframePath: thread.isGeneral ? nil : images.keyframe(thread),
                transcript: thread.isGeneral ? [] : send.transcripts[thread.id] ?? [],
                history: thread.messages.filter { !now.contains($0.id) && $0.state != .queued }.map {
                    HistoryPart(
                        id: $0.id, author: $0.author, kind: $0.kind, text: $0.text, region: $0.region,
                        cropPath: $0.region == nil ? nil : images.crop($0)
                    )
                },
                messages: work.map {
                    MessagePart(id: $0.id, text: $0.text, region: $0.region, cropPath: $0.region == nil ? nil : images.crop($0))
                }
            )
        }
        return SendPayload(
            send: SendPart(id: send.id, sentAt: send.sentAt),
            video: VideoPart(
                path: review.video.path, contentHash: review.video.contentHash,
                duration: (review.video.duration * 1000).rounded() / 1000, title: review.video.title
            ),
            context: context,
            threads: threads
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
