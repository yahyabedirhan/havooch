import Foundation

/// What `havooch wait` prints: one send as the listener reads it,
/// grouped by thread. Each thread carries its keyframe, its transcript
/// window as the send cut it, the conversation so far (`history`) and the
/// person's messages of this send. A send of a project's review carries
/// the project (decision E8): the version on screen, which `video` is,
/// and every version's path and label; each thread names its version,
/// with a `null` number for a removed version. On a plain video `project`
/// and each thread's `version` are `null`. A key with no value is `null`,
/// never left out.
///
///     { "send":    { "id": "s-f92cbb2a-2", "sentAt": "2026-10-05T19:02:11Z" },
///       "video":   { "path": "/abs/sample.mp4", "contentHash": "…", "duration": 21.233, "title": "sample.mp4" },
///       "project": { "slug": "launch-video", "title": "Launch video", "onScreen": 2,
///                    "versions": [ { "number": 1, "path": "/abs/cut1.mp4", "label": null }, … ] },
///       "context": null,
///       "threads": [ { "id": "t-f92cbb2a-1", "number": 1, "time": 10.017, "keyframePath": "/abs/….png",
///                      "version": { "number": 1, "path": "/abs/cut1.mp4", "label": null },
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

    /// A version of the project, as the listener reads it.
    public struct VersionPart: Codable, Equatable, Sendable {
        /// Its number (from 1); `null` for a version whose path left the
        /// project's list.
        public var number: Int?
        public var path: String
        public var label: String?

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(number, forKey: .number)
            try container.encode(path, forKey: .path)
            try container.encode(label, forKey: .label)
        }
    }

    /// The project a send of a project's review is on.
    public struct ProjectPart: Codable, Equatable, Sendable {
        public var slug: String
        public var title: String
        /// The number of the version on screen when the person sent;
        /// `null` when its path has left the list.
        public var onScreen: Int?
        /// Every version, v1 first.
        public var versions: [VersionPart]

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(slug, forKey: .slug)
            try container.encode(title, forKey: .title)
            try container.encode(onScreen, forKey: .onScreen)
            try container.encode(versions, forKey: .versions)
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
        /// The version the thread was raised on, in a project; `null` on a
        /// plain video and on General.
        public var version: VersionPart?
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
            try container.encode(version, forKey: .version)
            try container.encode(transcript, forKey: .transcript)
            try container.encode(history, forKey: .history)
            try container.encode(messages, forKey: .messages)
        }
    }

    public var send: SendPart
    /// The video on screen when the person sent.
    public var video: VideoPart
    /// The project of a project's review; `null` on a plain video.
    public var project: ProjectPart?
    /// The video's context text; `null` when this listener session already
    /// has it unchanged, or when there is none.
    public var context: String?
    /// General first, then the threads in time order.
    public var threads: [ThreadPart]

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(send, forKey: .send)
        try container.encode(video, forKey: .video)
        try container.encode(project, forKey: .project)
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
    /// `project` is the project's list as it is now, for a project's
    /// review; the version on screen is the one the send kept.
    public static func assemble(
        review: Review, send: Send, context: String?, images: Images, project: ProjectOutline? = nil
    ) -> SendPayload {
        func version(_ anchor: VersionAnchor) -> VersionPart {
            let number = project?.number(of: anchor.path)
            return VersionPart(number: number, path: anchor.path, label: number.flatMap { project?.version($0)?.label })
        }
        let threads = review.threads.compactMap { thread -> ThreadPart? in
            let work = thread.messages.filter { $0.sendID == send.id && $0.state?.isFinal == false }
            guard !work.isEmpty else { return nil }
            let now = Set(work.map(\.id))
            return ThreadPart(
                id: thread.id, number: thread.number, time: thread.time,
                keyframePath: thread.isGeneral ? nil : images.keyframe(thread),
                version: thread.anchor.map(version),
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
        let shown = send.onScreen.flatMap { review.video(at: $0.path) } ?? review.video
        return SendPayload(
            send: SendPart(id: send.id, sentAt: send.sentAt),
            video: VideoPart(
                path: shown.path, contentHash: shown.contentHash,
                duration: (shown.duration * 1000).rounded() / 1000, title: shown.title
            ),
            project: project.map { project in
                ProjectPart(
                    slug: project.slug, title: project.title, onScreen: send.onScreen.flatMap { project.number(of: $0.path) },
                    versions: project.versions.enumerated().map {
                        VersionPart(number: $0.offset + 1, path: $0.element.path, label: $0.element.label)
                    }
                )
            },
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
