import Foundation
import ReviewCore
import ReviewLease
import ReviewStore
import ReviewWire

/// What the app shows, for `state` and `app status`: as one JSON object
/// with `--json`, as lines otherwise. Keys that have no value are `null`,
/// never left out, so a reader can tell "nothing" from "not reported".
nonisolated struct StateReport: Encodable, Equatable {
    struct App: Encodable, Equatable {
        var version: String
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

    /// The open popover's message, still being written: view state, never
    /// kept.
    struct Popover: Encodable, Equatable {
        /// The thread it writes to: its number, or the number a new thread
        /// will take.
        var thread: Int?
        var time: Double
        var text: String
        /// The region the message is about; `null` for the whole frame.
        var region: Region?

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(thread, forKey: .thread)
            try container.encode(time, forKey: .time)
            try container.encode(text, forKey: .text)
            try container.encode(region, forKey: .region)
        }

        private enum CodingKeys: String, CodingKey {
            case thread, time, text, region
        }
    }

    /// One thread: its number, its frame and keyframe, its state and its
    /// messages in the order written.
    struct Thread: Encodable, Equatable {
        var id: String
        var number: Int
        /// The frame time; `null` for General.
        var time: Double?
        /// The state of its latest open person message; `null` with no
        /// person message.
        var state: String?
        /// The PNG of the frame; `null` for General.
        var keyframePath: String?
        /// Where the person left its popover; `null` until they move it.
        var popoverFrame: PopoverFrame?
        var messages: [Message]

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try container.encode(number, forKey: .number)
            try container.encode(time, forKey: .time)
            try container.encode(state, forKey: .state)
            try container.encode(keyframePath, forKey: .keyframePath)
            try container.encode(popoverFrame, forKey: .popoverFrame)
            try container.encode(messages, forKey: .messages)
        }

        private enum CodingKeys: String, CodingKey {
            case id, number, time, state, keyframePath, popoverFrame, messages
        }

        /// `thread` of the video with `contentHash`, whose pictures are
        /// where `layout` says.
        init(_ thread: ReviewThread, contentHash: String, layout: SupportLayout) {
            id = thread.id.text
            number = thread.number
            time = thread.time
            state = thread.state?.rawValue
            keyframePath = layout.keyframe(of: thread, on: contentHash)?.path
            popoverFrame = thread.popoverFrame
            messages = thread.messages.map { Message($0, contentHash: contentHash, layout: layout) }
        }
    }

    /// One message: who wrote it (`person` or `agent`), what it is
    /// (`message`, `question` or `answer`), and for a person's message its
    /// state, region, crop and send.
    struct Message: Encodable, Equatable {
        var id: String
        var author: String
        var kind: String
        var text: String
        var at: Date
        var state: String?
        /// The part of the frame it points at, 0 to 1 from the frame's
        /// top-left corner; `null` for the whole frame.
        var region: Region?
        /// The PNG of the region, cut from the keyframe; `null` with no
        /// region.
        var cropPath: String?
        /// The send it went out in; `null` while it's queued, and for
        /// every message but a person's `message`.
        var sendId: String?

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try container.encode(author, forKey: .author)
            try container.encode(kind, forKey: .kind)
            try container.encode(text, forKey: .text)
            try container.encode(at, forKey: .at)
            try container.encode(state, forKey: .state)
            try container.encode(region, forKey: .region)
            try container.encode(cropPath, forKey: .cropPath)
            try container.encode(sendId, forKey: .sendId)
        }

        private enum CodingKeys: String, CodingKey {
            case id, author, kind, text, at, state, region, cropPath, sendId
        }

        init(_ message: ReviewCore.Message, contentHash: String, layout: SupportLayout) {
            id = message.id.text
            author = message.author.rawValue
            kind = message.kind.rawValue
            text = message.text
            at = message.at
            state = message.state?.rawValue
            region = message.region
            cropPath = layout.crop(of: message, on: contentHash)?.path
            sendId = message.sendID?.text
        }
    }

    /// The person's messages one send delivered together.
    struct Send: Encodable, Equatable {
        var id: String
        var sentAt: Date
        var messageIds: [String]
        /// The threads the messages are on, General first, then in time
        /// order.
        var threadIds: [String]

        init(_ send: ReviewCore.Send, in review: VideoReview) {
            id = send.id.text
            sentAt = send.sentAt
            messageIds = send.messageIDs.map(\.text)
            var threads: [String] = []
            for (_, thread) in review.messages(of: send.id) where !threads.contains(thread.text) {
                threads.append(thread.text)
            }
            threadIds = threads
        }
    }

    /// The agent that receives the sends.
    struct Listener: Encodable, Equatable {
        /// `listening`, `working` or `absent`.
        var presence: String
        /// Whether a `wait` is open now.
        var waitOpen: Bool
        /// The name of the agent of the last `wait`; `null` before the
        /// first one.
        var session: String?
        /// The sends made and not yet taken by a `wait`.
        var pendingSends: Int
        /// The sends a `wait` took that aren't finished.
        var takenSends: Int

        /// Nobody has listened yet.
        static let absent = Listener(presence: "absent", waitOpen: false, session: nil, pendingSends: 0, takenSends: 0)

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(presence, forKey: .presence)
            try container.encode(waitOpen, forKey: .waitOpen)
            try container.encode(session, forKey: .session)
            try container.encode(pendingSends, forKey: .pendingSends)
            try container.encode(takenSends, forKey: .takenSends)
        }

        private enum CodingKeys: String, CodingKey {
            case presence, waitOpen, session, pendingSends, takenSends
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

    /// The sidebar: the thread it shows and the kept width.
    struct Sidebar: Encodable, Equatable {
        /// The id of the thread the sidebar shows in its thread view;
        /// `null` while it shows the thread list.
        var thread: String?
        /// The sidebar's width in points, as it is kept in the settings.
        var width: Double

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(thread, forKey: .thread)
            try container.encode(width, forKey: .width)
        }

        private enum CodingKeys: String, CodingKey {
            case thread, width
        }
    }

    var app: App
    /// Who drives the app; `null` while nobody does. The control server,
    /// which owns the lease, fills it in.
    var lease: ControlLease.Status?
    /// Whether an agent listens for sends. The control server, which
    /// answers the listener, fills it in.
    var listener = Listener.absent
    /// The active theme; the app's model fills it in.
    var theme: Theme?
    /// The open video; `null` with none.
    var video: Video?
    var player: Player
    /// The open video's transcript; `null` with no video. The app's model
    /// fills it in.
    var transcript: Transcript?
    /// The message being written; `null` while the popover is closed.
    var popover: Popover?
    /// The sidebar; the app's model fills it in.
    var sidebar: Sidebar?
    /// The open video's threads: General first, then in time order.
    var threads: [Thread]
    /// The ids of the messages waiting to be sent, in the threads' order.
    var queue: [String]
    /// The open video's sends, in the order they were sent.
    var sends: [Send]

    init(
        app: App, lease: ControlLease.Status? = nil, video: Video?, player: Player, popover: Popover? = nil,
        threads: [Thread] = [], queue: [String] = [], sends: [Send] = []
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
        self.popover = popover
        self.threads = threads
        self.queue = queue
        self.sends = sends
    }

    private enum CodingKeys: String, CodingKey {
        case app, lease, listener, video, player, popover, threads, queue, sends
        case transcript, theme, sidebar
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(app, forKey: .app)
        try container.encode(lease, forKey: .lease)
        try container.encode(listener, forKey: .listener)
        try container.encode(theme, forKey: .theme)
        try container.encode(video, forKey: .video)
        try container.encode(player, forKey: .player)
        try container.encode(transcript, forKey: .transcript)
        try container.encode(popover, forKey: .popover)
        try container.encode(sidebar, forKey: .sidebar)
        try container.encode(threads, forKey: .threads)
        try container.encode(queue, forKey: .queue)
        try container.encode(sends, forKey: .sends)
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
        \(theme.map { $0.line + "\n" } ?? "")threads: \(threadLines)

        """
    }

    /// `listener: listening (Claude Code), 0 sends waiting, 1 taken`.
    private var listenerLine: String {
        let who = listener.session.map { " (\($0))" } ?? ""
        let waiting = "\(listener.pendingSends) \(listener.pendingSends == 1 ? "send" : "sends") waiting"
        return "listener: \(listener.presence)\(who), \(waiting), \(listener.takenSends) taken"
    }

    /// The threads, one line each with their messages under them.
    private var threadLines: String {
        let lines = threads.flatMap { thread in
            let place = thread.time.map { "#\(thread.number) at \(TimeCode.text($0))" } ?? "#0 General"
            let head = "  \(place) \(thread.id) \(thread.state ?? "-")"
            return [head] + thread.messages.map { message in
                let region = message.region.map { " region \($0.text)" } ?? ""
                let state = message.state.map { " \($0)" } ?? ""
                return "    \(message.id) \(message.author) \(message.kind)\(state)\(region): \(message.text.replacing("\n", with: " "))"
            }
        }
        return (["\(threads.count) (\(queue.count) queued)"] + lines).joined(separator: "\n")
    }

    // MARK: - app status

    /// `app status --json`.
    var statusJSON: String {
        Self.json(Status(
            running: true, version: app.version, demo: app.demo, support: app.support,
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
        var demo: Bool
        var support: String
        var video: String?
        var lease: ControlLease.Status?

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(running, forKey: .running)
            try container.encode(version, forKey: .version)
            try container.encode(demo, forKey: .demo)
            try container.encode(support, forKey: .support)
            try container.encode(video, forKey: .video)
            try container.encode(lease, forKey: .lease)
        }

        private enum CodingKeys: String, CodingKey {
            case running, version, demo, support, video, lease
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
