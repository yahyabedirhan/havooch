import Foundation
import VRLease
import VRReview
import VRWire

/// What the app shows, as `state` and `app status` report it: as lines for a
/// person, or as one JSON object. Built from the model and the lease at the
/// moment of asking. Each later ticket adds its own keys (the listener, the
/// context, the transcript, the batches).
struct StateReport: Equatable {
    struct Player: Encodable, Equatable {
        /// Where the player is, in seconds, to the millisecond.
        var time: Double
        var playing: Bool
    }

    /// The folder a demo run reads, or nil for the person's own app.
    var demo: String?
    /// The lease, or nil when it's free.
    var lease: LeaseStatus?
    /// The open video, or nil when there's none.
    var video: VideoInfo?
    var player: Player
    /// Every comment of the open video, drafts included, in time order.
    var comments: [CommentReport]

    /// The ids of the comments waiting to be sent, in time order.
    var queue: [String] {
        comments.filter { $0.state == .queued }.map(\.id)
    }

    @MainActor
    init(model: ReviewModel, lease: LeaseStatus?) {
        demo = model.demoFolder?.path
        self.lease = lease
        video = model.video?.info
        player = Player(time: TimeText.rounded(model.time), playing: model.isPlaying)
        comments = (model.session?.comments ?? []).map { CommentReport($0, keyframe: model.keyframeURL(for: $0.id)) }
    }

    // MARK: - state

    /// `state --json`. `lease`, `video` and `app.demo` are `null` when
    /// there's none, never left out. The player's time is at `player.time`
    /// and, for a script that reads one field, at the top-level `time`.
    var stateJSON: String {
        JSONLine.string(State(report: self))
    }

    /// `state` as lines; the comments only when there are some:
    ///
    ///     video: sample (0:21.248) /Users/me/sample.mp4
    ///     player: paused at 0:10.000
    ///     comments: 2, 1 queued
    ///       c1 queued at 0:10.000: too fast
    ///       c2 draft at 0:12.000:
    ///     lease: free
    var stateText: String {
        var lines: [String] = []
        if let video {
            lines.append("video: \(video.title) (\(TimeText.exact(video.duration))) \(video.path)")
            lines.append("player: \(player.playing ? "playing" : "paused") at \(TimeText.exact(player.time))")
        } else {
            lines.append("video: none")
        }
        if !comments.isEmpty {
            lines.append("comments: \(comments.count), \(queue.count) queued")
            lines += comments.map { comment in
                let text = comment.text.split(whereSeparator: \.isNewline).joined(separator: " ")
                return "  \(comment.id) \(comment.state.rawValue) at \(TimeText.exact(comment.time)): \(text)"
            }
        }
        lines.append(leaseLine)
        if let demo { lines.append("demo: \(demo)") }
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: - app status

    /// `app status --json`: `{running, version, variant, demo, lease, video}`.
    var statusJSON: String {
        JSONLine.string(Status(report: self))
    }

    /// `app status` as lines; `demo` only in a demo run:
    ///
    ///     video-review 0.1.0 (proto-3) is running
    ///     demo: /Users/me/repo/fixtures/sample
    ///     lease: free
    ///     video: sample, paused at 0:10.000 of 0:21.248
    var statusText: String {
        var lines = ["video-review \(AppIdentity.versionText) is running"]
        if let demo { lines.append("demo: \(demo)") }
        lines.append(leaseLine)
        if let video {
            let doing = player.playing ? "playing" : "paused"
            lines.append("video: \(video.title), \(doing) at \(TimeText.exact(player.time)) of \(TimeText.exact(video.duration))")
        } else {
            lines.append("video: none")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private var leaseLine: String {
        guard let lease else { return "lease: free" }
        return "lease: \(lease.holder) in \(lease.place), \(lease.secondsLeft)s left, \(lease.waiting) waiting"
    }

    // MARK: - The JSON shapes

    private struct State: Encodable {
        var report: StateReport

        enum Keys: String, CodingKey { case app, lease, video, player, time, queue, comments }
        enum AppKeys: String, CodingKey { case version, variant, demo }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: Keys.self)
            var app = container.nestedContainer(keyedBy: AppKeys.self, forKey: .app)
            try app.encode(AppIdentity.version, forKey: .version)
            try app.encode(AppIdentity.variant, forKey: .variant)
            try app.encode(report.demo, forKey: .demo)
            try container.encode(report.lease, forKey: .lease)
            try container.encode(report.video, forKey: .video)
            try container.encode(report.player, forKey: .player)
            try container.encode(report.player.time, forKey: .time)
            try container.encode(report.queue, forKey: .queue)
            try container.encode(report.comments, forKey: .comments)
        }
    }

    private struct Status: Encodable {
        var report: StateReport

        enum Keys: String, CodingKey { case running, version, variant, demo, lease, video }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: Keys.self)
            // Always true: a status only comes from a running app. It's in
            // the JSON so an agent reads one field, not the exit status alone.
            try container.encode(true, forKey: .running)
            try container.encode(AppIdentity.version, forKey: .version)
            try container.encode(AppIdentity.variant, forKey: .variant)
            try container.encode(report.demo, forKey: .demo)
            try container.encode(report.lease, forKey: .lease)
            try container.encode(report.video, forKey: .video)
        }
    }
}

/// One comment as `state` and `comment add` report it: `{id, time, text,
/// state, keyframePath}`. `keyframePath` is the keyframe's absolute path, or
/// `null` while the file isn't on disk.
struct CommentReport: Encodable, Equatable {
    var id: String
    var time: Double
    var text: String
    var state: CommentState
    var keyframePath: String?

    init(_ comment: Comment, keyframe: URL?) {
        id = comment.id
        time = comment.time
        text = comment.text
        state = comment.state
        keyframePath = keyframe?.path
    }

    enum Keys: String, CodingKey { case id, time, text, state, keyframePath }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: Keys.self)
        try container.encode(id, forKey: .id)
        try container.encode(time, forKey: .time)
        try container.encode(text, forKey: .text)
        try container.encode(state, forKey: .state)
        // Encoded also when nil: `null`, never left out.
        try container.encode(keyframePath, forKey: .keyframePath)
    }
}

/// A value as one JSON object on one line, keys sorted: what every command
/// prints with `--json`.
enum JSONLine {
    static func string(_ value: some Encodable) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        // The values encoded here are strings, numbers and booleans.
        return String(decoding: try! encoder.encode(value), as: UTF8.self) + "\n"
    }
}
