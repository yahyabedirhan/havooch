import Foundation
import ReviewCore
import ReviewLease
import ReviewWire

/// What the app shows, for `state` and `app status`: as one JSON object
/// with `--json`, as lines otherwise. Keys that have no value are `null`,
/// never left out, so a reader can tell "nothing" from "not reported".
struct StateReport: Encodable, Equatable {
    struct App: Encodable, Equatable {
        var version: String
        var variant: String
        /// Whether the app runs on a demo's data.
        var demo: Bool
        /// The support folder this run keeps its data in.
        var support: String
    }

    struct Video: Encodable, Equatable {
        var path: String
        var contentHash: String
        var title: String
        var duration: Double
        /// The person's context note for the agent; empty for none.
        var contextNote = ""
    }

    /// The comment still in the comment box.
    struct Draft: Encodable, Equatable {
        var time: Double
        var text: String
        /// The region the comment is about; `null` for the whole frame.
        var region: Region?

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(time, forKey: .time)
            try container.encode(text, forKey: .text)
            try container.encode(region, forKey: .region)
        }

        private enum CodingKeys: String, CodingKey {
            case time, text, region
        }
    }

    struct Comment: Encodable, Equatable {
        var id: String
        var time: Double
        var text: String
        var state: String
        /// The PNG of the frame at `time`.
        var keyframePath: String
        /// The part of the frame the comment points at, 0 to 1 from the
        /// frame's top-left corner; `null` for the whole frame.
        var region: Region?
        /// The PNG of the region, cut from the keyframe; `null` with no
        /// region.
        var cropPath: String?
        /// The batch the comment was sent in; `null` while it's queued.
        var batchId: String?

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try container.encode(time, forKey: .time)
            try container.encode(text, forKey: .text)
            try container.encode(state, forKey: .state)
            try container.encode(keyframePath, forKey: .keyframePath)
            try container.encode(region, forKey: .region)
            try container.encode(cropPath, forKey: .cropPath)
            try container.encode(batchId, forKey: .batchId)
        }

        private enum CodingKeys: String, CodingKey {
            case id, time, text, state, keyframePath, region, cropPath, batchId
        }
    }

    /// The comments one send delivered together.
    struct Batch: Encodable, Equatable {
        var id: String
        var sentAt: Date
        /// The batch's comments, in time order.
        var commentIds: [String]
    }

    /// The agent that receives the batches.
    struct Listener: Encodable, Equatable {
        /// `listening`, `working` or `absent`.
        var presence: String
        /// Whether a `wait` is open now.
        var waitOpen: Bool
        /// The name of the agent of the last `wait`; `null` before the
        /// first one.
        var session: String?
        /// The batches sent and not yet taken by a `wait`.
        var pendingBatches: Int
        /// The batches a `wait` took that aren't finished.
        var takenBatches: Int

        /// Nobody has listened yet.
        static let absent = Listener(presence: "absent", waitOpen: false, session: nil, pendingBatches: 0, takenBatches: 0)

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(presence, forKey: .presence)
            try container.encode(waitOpen, forKey: .waitOpen)
            try container.encode(session, forKey: .session)
            try container.encode(pendingBatches, forKey: .pendingBatches)
            try container.encode(takenBatches, forKey: .takenBatches)
        }

        private enum CodingKeys: String, CodingKey {
            case presence, waitOpen, session, pendingBatches, takenBatches
        }
    }

    struct Player: Encodable, Equatable {
        var time: Double
        var playing: Bool
    }

    /// The open video's transcript: where it comes from and how far it is.
    struct Transcript: Encodable, Equatable {
        /// `voiceover`, `subtitles` or `speech`.
        var source: String
        /// Whether every line is there. False while speech is still being
        /// transcribed, and when that gave up.
        var complete: Bool
        /// How many lines there are now.
        var lines: Int
        /// Why the transcription gave up; `null` otherwise.
        var problem: String?

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(source, forKey: .source)
            try container.encode(complete, forKey: .complete)
            try container.encode(lines, forKey: .lines)
            try container.encode(problem, forKey: .problem)
        }

        private enum CodingKeys: String, CodingKey {
            case source, complete, lines, problem
        }

        /// `voiceover, 3 lines, complete`.
        var line: String {
            let progress = problem.map { "stopped: \($0)" } ?? (complete ? "complete" : "transcribing")
            return "\(source), \(lines) \(lines == 1 ? "line" : "lines"), \(progress)"
        }
    }

    var app: App
    /// Who drives the app; `null` while nobody does. The control server,
    /// which owns the lease, fills it in.
    var lease: ControlLease.Status?
    /// Whether an agent listens for batches. The control server, which
    /// answers the listener, fills it in.
    var listener = Listener.absent
    /// The open video; `null` with none.
    var video: Video?
    var player: Player
    /// The open video's transcript; `null` with no video. The app's model
    /// fills it in.
    var transcript: Transcript?
    /// The comment being written; `null` while the comment box is closed.
    var draft: Draft?
    /// The open video's comments, in time order.
    var comments: [Comment]
    /// The open video's batches, in the order they were sent.
    var batches: [Batch]

    /// The ids of the comments waiting to be sent, in time order.
    var queue: [String] {
        comments.filter { $0.state == "queued" }.map(\.id)
    }

    init(
        app: App, lease: ControlLease.Status? = nil, video: Video?, player: Player, draft: Draft? = nil,
        comments: [Comment] = [], batches: [Batch] = []
    ) {
        self.app = app
        self.lease = lease
        self.video = video.map {
            Video(
                path: $0.path, contentHash: $0.contentHash, title: $0.title, duration: Self.milliseconds($0.duration),
                contextNote: $0.contextNote
            )
        }
        self.player = Player(time: Self.milliseconds(player.time), playing: player.playing)
        self.draft = draft
        self.comments = comments
        self.batches = batches
    }

    private enum CodingKeys: String, CodingKey {
        case app, lease, listener, video, player, draft, comments, queue, batches
        case transcript
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(app, forKey: .app)
        try container.encode(lease, forKey: .lease)
        try container.encode(listener, forKey: .listener)
        try container.encode(video, forKey: .video)
        try container.encode(player, forKey: .player)
        try container.encode(transcript, forKey: .transcript)
        try container.encode(draft, forKey: .draft)
        try container.encode(comments, forKey: .comments)
        try container.encode(queue, forKey: .queue)
        try container.encode(batches, forKey: .batches)
    }

    // MARK: - state

    /// `state --json`.
    var json: String { Self.json(self) }

    /// `state`.
    var lines: String {
        """
        \(AppIdentity.appName) \(app.version), \(app.demo ? "demo data" : "your data") in \(app.support)
        video: \(video.map { "\($0.title) (\(TimeCode.text($0.duration))) \($0.path)" } ?? "none")
        player: \(player.playing ? "playing" : "paused") at \(TimeCode.text(player.time))
        transcript: \(transcript?.line ?? "none")
        \(leaseLine)
        \(listenerLine)
        comments: \(commentLines)

        """
    }

    /// `listener: listening (Claude Code), 0 batches waiting, 1 taken`.
    private var listenerLine: String {
        let who = listener.session.map { " (\($0))" } ?? ""
        let waiting = "\(listener.pendingBatches) \(listener.pendingBatches == 1 ? "batch" : "batches") waiting"
        return "listener: \(listener.presence)\(who), \(waiting), \(listener.takenBatches) taken"
    }

    /// The comments, one line each under their count.
    private var commentLines: String {
        guard !comments.isEmpty else { return "none" }
        let lines = comments.map {
            let region = $0.region.map { " region \($0.text)" } ?? ""
            return "  \($0.id) \(TimeCode.text($0.time))\(region) \($0.state): \($0.text.replacing("\n", with: " "))"
        }
        return (["\(comments.count) (\(queue.count) queued)"] + lines).joined(separator: "\n")
    }

    // MARK: - app status

    /// `app status --json`.
    var statusJSON: String {
        Self.json(Status(
            running: true, version: app.version, variant: app.variant, demo: app.demo, support: app.support,
            video: video?.path, lease: lease
        ))
    }

    /// `app status`, and what `app open` prints.
    var statusLines: String {
        """
        running: \(AppIdentity.appName) \(app.version)
        data: \(app.demo ? "demo" : "yours"), \(app.support)
        video: \(video?.path ?? "none")
        \(leaseLine)

        """
    }

    /// `lease: held by Claude Code in /work, 48s left, 0 waiting`, or
    /// `lease: free`.
    private var leaseLine: String {
        "lease: " + (lease.map {
            "held by \($0.holder.name) in \($0.holder.place), \($0.secondsLeft)s left, \($0.waiting) waiting"
        } ?? "free")
    }

    private struct Status: Encodable {
        var running: Bool
        var version: String
        var variant: String
        var demo: Bool
        var support: String
        var video: String?
        var lease: ControlLease.Status?

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(running, forKey: .running)
            try container.encode(version, forKey: .version)
            try container.encode(variant, forKey: .variant)
            try container.encode(demo, forKey: .demo)
            try container.encode(support, forKey: .support)
            try container.encode(video, forKey: .video)
            try container.encode(lease, forKey: .lease)
        }

        private enum CodingKeys: String, CodingKey {
            case running, version, variant, demo, support, video, lease
        }
    }

    // MARK: - JSON

    /// `value` as the JSON the command prints: readable, keys in order.
    static func json(_ value: some Encodable) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        // The reports are strings, numbers and booleans: encoding can't fail.
        return String(decoding: try! encoder.encode(value), as: UTF8.self) + "\n"
    }

    /// `seconds` to the millisecond: a time read back from the player
    /// carries the noise of its timescale.
    private static func milliseconds(_ seconds: Double) -> Double {
        (seconds * 1000).rounded() / 1000
    }
}
