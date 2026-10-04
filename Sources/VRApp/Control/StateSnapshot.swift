import Foundation
import VRLease
import VRReview
import VRWire

/// What `state` prints: everything the window shows, as one JSON object
/// with sorted keys. `AppModel.snapshot` builds it. A part with nothing in
/// it is written as `null` or as an empty list, never left out, so an agent
/// reads the same keys every time.
struct StateSnapshot: Encodable {
    struct App: Encodable {
        var version: String
        var variant: String
        /// Whether this run is on a demo folder.
        var demo: Bool
        /// The folder this run keeps its data in.
        var support: String
    }

    struct Video: Encodable {
        var path: String
        /// The hash that names the video whatever its file is called.
        @Nulled var contentHash: String?
        var title: String
        var duration: Double
    }

    struct Player: Encodable {
        var time: Double
        var playing: Bool
        /// The speed playback runs at while it plays.
        var rate: Double
    }

    struct Context: Encodable {
        @Nulled var sidecarPath: String?
        var note: String
    }

    /// Where the open video's transcript stands.
    struct Transcript: Encodable {
        /// `voiceover`, `subtitles` or `speech`.
        @Nulled var source: String?
        /// Whether the source has every line: false while speech
        /// recognition runs.
        var complete: Bool
        /// How many lines there are so far, in the whole video.
        var lines: Int
        /// Why the source stopped before it had every line.
        @Nulled var problem: String?
    }

    struct Listener: Encodable {
        var presence: String
        @Nulled var name: String?
        @Nulled var place: String?
    }

    /// The comment being written in the comment box.
    struct Draft: Encodable {
        var time: Double
        /// The part of the frame it points at, as `{x, y, w, h}` from 0 to 1.
        @Nulled var region: Region?
    }

    /// One comment, as `state` lists it and as `comment add --json` prints it.
    struct Comment: Encodable {
        var id: String
        var time: Double
        var text: String
        /// The part of the frame it points at, as `{x, y, w, h}` from 0 to 1.
        @Nulled var region: Region?
        var state: String
        @Nulled var batchId: String?
        /// The PNG of the frame at `time`, as an absolute path.
        var keyframePath: String
        /// The PNG of that part of the keyframe, as an absolute path.
        @Nulled var cropPath: String?
        var thread: [ThreadMessage]
    }

    /// One batch of the open video, in the order they were sent.
    struct Batch: Encodable {
        var id: String
        var sentAt: Date
        var commentIds: [String]
        /// Where it stands on its way to the listener: `pending`, `taken`
        /// or `finished`.
        var delivery: String
        var thread: [ThreadMessage]
    }

    /// The agent message the window announces right now.
    struct Notice: Encodable {
        var batchId: String
        /// The comment it is on; `null` for a message about the whole batch.
        @Nulled var commentId: String?
        /// `message` or `question`.
        var kind: String
        var text: String
    }

    var app: App
    @Nulled var video: Video?
    var player: Player
    @Nulled var draft: Draft?
    /// The open video's comments, in time order.
    var comments: [Comment] = []
    /// The ids of the queued ones, in the same order.
    var queue: [String] = []
    var batches: [Batch] = []
    var context = Context(sidecarPath: nil, note: "")
    var transcript = Transcript(source: nil, complete: false, lines: 0, problem: nil)
    var listener = Listener(presence: "absent", name: nil, place: nil)
    @Nulled var lease: ControlLease.Status?
    @Nulled var notice: Notice?

    /// The snapshot as one line of JSON.
    var json: String { JSONText.line(self) }

    /// What `app status` reports: the snapshot's parts that say whether
    /// and how the app runs.
    var status: Status {
        Status(
            version: app.version, variant: app.variant, demo: app.demo, support: app.support,
            video: video, playerTime: player.time, playing: player.playing, lease: lease, listener: listener
        )
    }

    struct Status: Encodable {
        /// Always true: a status only comes from a running app. It's in the
        /// JSON so an agent reads one field, not the exit code alone.
        var running = true
        var version: String
        var variant: String
        var demo: Bool
        var support: String
        @Nulled var video: Video?
        var playerTime: Double
        var playing: Bool
        @Nulled var lease: ControlLease.Status?
        var listener: Listener

        private enum CodingKeys: String, CodingKey {
            case running, version, variant, demo, support, video, lease, listener
        }

        var json: String { JSONText.line(self) }

        /// The status as lines, for a person:
        ///
        ///     Video Review (proto-1) 0.1.0 is running
        ///     variant: proto-1
        ///     data: demo, /Users/me/repo/.scratch/demo
        ///     video: /Users/me/repo/fixtures/sample/sample.mp4, paused at 0:10.000
        ///     lease: Claude Code in /Users/me/repo, 48s left, 0 waiting
        ///     listener: absent
        var text: String {
            var lines = ["\(Identity.appName) \(version) is running"]
            lines.append("variant: \(variant.isEmpty ? "none" : variant)")
            lines.append("data: \(demo ? "demo" : "yours"), \(support)")
            if let video {
                lines.append("video: \(video.path), \(playing ? "playing" : "paused") at \(TimeText.precise(playerTime))")
            } else {
                lines.append("video: none")
            }
            if let lease {
                lines.append("lease: \(lease.holder) in \(lease.place), \(lease.secondsLeft)s left, \(lease.waiting) waiting")
            } else {
                lines.append("lease: free")
            }
            lines.append("listener: \(listener.presence)")
            return lines.joined(separator: "\n") + "\n"
        }
    }
}

/// An optional that is written as `null` when it's nil, where Swift's own
/// encoding would leave the key out.
@propertyWrapper
struct Nulled<Value: Encodable>: Encodable {
    var wrappedValue: Value?

    init(wrappedValue: Value?) {
        self.wrappedValue = wrappedValue
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        if let wrappedValue {
            try container.encode(wrappedValue)
        } else {
            try container.encodeNil()
        }
    }
}

/// The app's JSON output: one object on one line, keys sorted, slashes as
/// they are, dates as ISO 8601.
enum JSONText {
    static func line(_ value: some Encodable) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        // The values here are strings, numbers, booleans and lists of them.
        return String(decoding: try! encoder.encode(value), as: UTF8.self) + "\n"
    }
}
