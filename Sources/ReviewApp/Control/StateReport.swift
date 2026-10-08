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
        /// Whether the app is the active app, in front of the others:
        /// `havooch open` brings it there.
        var active = false
    }

    /// What the window shows: the player with a video open, else home.
    /// The home screen and the first launch's empty state are both home:
    /// the screen with no video. `none` while no window is open.
    enum Screen: String, Encodable, Equatable {
        case home, player, none
    }

    /// One window, as `window list` and `state` list it.
    struct Window: Encodable, Equatable {
        /// Its name for `--window`: `w1`.
        var id: String
        /// Whether commands without `--window` act on it: the window with
        /// the keys, else the one that had them last.
        var key: Bool
        /// Whether its window is on screen.
        var onScreen: Bool
        var screen: Screen
        /// The video it holds; `null` for none.
        var video: Held?
        /// The listener of the video it holds: `presence` and `session` as
        /// `listener` has them; `null` with no video.
        var listener: Heard?

        /// Whether an agent listens to a window's video, and which.
        struct Heard: Encodable, Equatable {
            var presence: String
            var session: String?

            func encode(to encoder: any Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(presence, forKey: .presence)
                try container.encode(session, forKey: .session)
            }

            private enum CodingKeys: String, CodingKey {
                case presence, session
            }
        }

        /// The video a window holds.
        struct Held: Encodable, Equatable {
            var path: String
            var title: String
            var contentHash: String
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try container.encode(key, forKey: .key)
            try container.encode(onScreen, forKey: .onScreen)
            try container.encode(screen, forKey: .screen)
            try container.encode(video, forKey: .video)
            try container.encode(listener, forKey: .listener)
        }

        private enum CodingKeys: String, CodingKey {
            case id, key, onScreen, screen, video, listener
        }

        /// `w1 key player cut1.mp4 /Movies/cut1.mp4`, or `w2 home off screen`.
        var line: String {
            let held = video.map { " \($0.title) \($0.path)" } ?? ""
            let heard = listener.map { " listener \($0.presence)" + ($0.session.map { " (\($0))" } ?? "") } ?? ""
            return "\(id)\(key ? " key" : "") \(screen.rawValue)\(onScreen ? "" : " off screen")\(held)\(heard)"
        }
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
        /// Whether an agent message came after the person last opened
        /// the thread's view: its row shows the unread dot.
        var unread: Bool
        var messages: [Message]

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try container.encode(number, forKey: .number)
            try container.encode(time, forKey: .time)
            try container.encode(state, forKey: .state)
            try container.encode(keyframePath, forKey: .keyframePath)
            try container.encode(popoverFrame, forKey: .popoverFrame)
            try container.encode(unread, forKey: .unread)
            try container.encode(messages, forKey: .messages)
        }

        private enum CodingKeys: String, CodingKey {
            case id, number, time, state, keyframePath, popoverFrame, unread, messages
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
            unread = thread.isUnread
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
        /// A question's quick-reply choices, in order; left out of the JSON
        /// for a question with none and for every other message.
        var choices: [String]?

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
            try container.encodeIfPresent(choices, forKey: .choices)
        }

        private enum CodingKeys: String, CodingKey {
            case id, author, kind, text, at, state, region, cropPath, sendId, choices
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
            choices = message.choices
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
        /// What the agent does now, the newest first: the live lines the
        /// thread views and the footer show. Empty while no agent is there.
        var activity: [Activity] = []
        /// The agent the listener took over from, when it replaced one
        /// that was there ("Codex took over from Claude Code"); `null` otherwise.
        var tookOverFrom: String?

        /// Nobody has listened yet.
        static let absent = Listener(presence: "absent", waitOpen: false, session: nil, pendingSends: 0, takenSends: 0)

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(presence, forKey: .presence)
            try container.encode(waitOpen, forKey: .waitOpen)
            try container.encode(session, forKey: .session)
            try container.encode(pendingSends, forKey: .pendingSends)
            try container.encode(takenSends, forKey: .takenSends)
            try container.encode(activity, forKey: .activity)
            try container.encode(tookOverFrom, forKey: .tookOverFrom)
        }

        private enum CodingKeys: String, CodingKey {
            case presence, waitOpen, session, pendingSends, takenSends, activity, tookOverFrom
        }
    }

    /// One live line: what the agent does now on a thread, for a message,
    /// as its last `status working` said it.
    struct Activity: Encodable, Equatable {
        var thread: String
        var message: String
        var text: String
    }

    struct Player: Encodable, Equatable {
        var time: Double
        var playing: Bool
    }

    /// One recent video, as the home screen shows it and `state` reports it.
    struct Recent: Encodable, Equatable {
        /// The absolute path it was last opened at.
        var path: String
        /// The file's name without its extension.
        var title: String
        var contentHash: String
        /// When the person last opened it.
        var openedAt: Date
        /// The playhead's last position, in seconds.
        var position: Double
        /// Whether the file is still at `path`.
        var available: Bool

        /// `video`, with whether its file is there now.
        init(_ video: RecentVideo) {
            let url = URL(fileURLWithPath: video.path)
            path = video.path
            title = url.deletingPathExtension().lastPathComponent
            contentHash = video.contentHash
            openedAt = video.openedAt
            position = StateReport.milliseconds(video.position)
            available = FileManager.default.fileExists(atPath: video.path)
        }

        var url: URL { URL(fileURLWithPath: path) }
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
        /// The composer at the sidebar's foot (L41); `null` with no video.
        var composer: Composer? = nil
        /// What the sidebar shows: `threads` (the thread list), `thread`
        /// (a thread's view) or `connect` (the Connect view, G1).
        var mode = "threads"
        /// The Connect view; `null` while it doesn't show.
        var connect: Connect? = nil

        /// The Connect view: what opened it, the outbox banner, the picked
        /// harness with its readiness and prompt, and the listener card.
        struct Connect: Encodable, Equatable {
            /// `pill`, `header` (the connect button and `connect show`) or
            /// `send` (Send with no agent there).
            var reason: String
            /// `none`, `connected` or `reconnecting` (G6).
            var phase: String
            /// The picked harness's install name: `claude-code`.
            var harness: String
            /// `ready`, `skillNotDetected` or `harnessNotDetected` (ADR 0005).
            var readiness: String
            /// The prompt to paste in the picked harness.
            var prompt: String?
            /// The outbox banner; `null` when Send didn't open the view.
            var banner: Banner? = nil
            /// The listener card; `null` while nobody listens or reconnects.
            var listener: Card? = nil

            /// "3 messages wait for an agent…" or "Delivered 3 messages to Claude Code".
            struct Banner: Encodable, Equatable {
                /// `waiting` or `delivered`.
                var kind: String
                var messages: Int
                /// The agent that took them; `null` while they wait.
                var agent: String?
                var text: String

                init(_ banner: OutboxBanner) {
                    text = banner.text
                    switch banner {
                    case .waiting(let messages): (kind, self.messages, agent) = ("waiting", messages, nil)
                    case .delivered(let messages, let to): (kind, self.messages, agent) = ("delivered", messages, to)
                    }
                }

                func encode(to encoder: any Encoder) throws {
                    var container = encoder.container(keyedBy: CodingKeys.self)
                    try container.encode(kind, forKey: .kind)
                    try container.encode(messages, forKey: .messages)
                    try container.encode(agent, forKey: .agent)
                    try container.encode(text, forKey: .text)
                }

                private enum CodingKeys: String, CodingKey {
                    case kind, messages, agent, text
                }
            }

            /// The listener card: the agent, where it runs, since when, and
            /// the prompt to listen again later (G7).
            struct Card: Encodable, Equatable {
                var agent: String
                /// A Herdr pane, else its working folder: what Copy Path copies.
                var place: String
                /// When its session's first `wait` opened; `null` when unknown.
                var since: Date?
                /// Until when it counts as reconnecting; `null` while connected.
                var reconnectingUntil: Date? = nil
                /// "To listen again later, paste this in <harness>:"; `null`
                /// for an agent Havooch doesn't set up.
                var prompt: String?

                init(_ session: ListenerSession, prompt: String?) {
                    agent = session.name
                    place = session.place
                    since = session.since
                    self.prompt = prompt
                }

                func encode(to encoder: any Encoder) throws {
                    var container = encoder.container(keyedBy: CodingKeys.self)
                    try container.encode(agent, forKey: .agent)
                    try container.encode(place, forKey: .place)
                    try container.encode(since, forKey: .since)
                    try container.encode(reconnectingUntil, forKey: .reconnectingUntil)
                    try container.encode(prompt, forKey: .prompt)
                }

                private enum CodingKeys: String, CodingKey {
                    case agent, place, since, reconnectingUntil, prompt
                }
            }

            func encode(to encoder: any Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(reason, forKey: .reason)
                try container.encode(phase, forKey: .phase)
                try container.encode(harness, forKey: .harness)
                try container.encode(readiness, forKey: .readiness)
                try container.encode(prompt, forKey: .prompt)
                try container.encode(banner, forKey: .banner)
                try container.encode(listener, forKey: .listener)
            }

            private enum CodingKeys: String, CodingKey {
                case reason, phase, harness, readiness, prompt, banner, listener
            }
        }

        /// Where the composer's words go, and what it holds.
        struct Composer: Encodable, Equatable {
            /// What the composer says it writes to, as it shows it: "New
            /// thread at 0:12", "Reply on #3", "Reply on General", "Follow
            /// up on #3", "Answer #3 · goes at once".
            var target: String
            /// `new` (a new thread at the frame), `reply` (from the thread
            /// list), `follow-up` (from a thread view) or `answer` (at once).
            var kind: String
            /// The id of the thread the words go on; `null` for a new thread.
            var thread: String?
            /// The thread's number, or the number a new thread will take.
            var number: Int
            /// The frame the words are on; `null` for General.
            var time: Double?
            /// Whether the General toggle is on.
            var general: Bool
            /// The words in the field: the target's draft.
            var text: String
            /// The region chip that goes with the words; `null` for none.
            var region: Region?

            func encode(to encoder: any Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(target, forKey: .target)
                try container.encode(kind, forKey: .kind)
                try container.encode(thread, forKey: .thread)
                try container.encode(number, forKey: .number)
                try container.encode(time, forKey: .time)
                try container.encode(general, forKey: .general)
                try container.encode(text, forKey: .text)
                try container.encode(region, forKey: .region)
            }

            private enum CodingKeys: String, CodingKey {
                case target, kind, thread, number, time, general, text, region
            }
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(mode, forKey: .mode)
            try container.encode(thread, forKey: .thread)
            try container.encode(width, forKey: .width)
            try container.encode(composer, forKey: .composer)
            try container.encode(connect, forKey: .connect)
        }

        private enum CodingKeys: String, CodingKey {
            case mode, thread, width, composer, connect
        }
    }

    /// The setup tour over the stage, and "Finish setup" in the header (H4,
    /// P11).
    struct Tour: Encodable, Equatable {
        /// Whether the tour's panel shows.
        var open: Bool
        /// `tools`, `connect`, `write`, `send` or `reply`: the step it
        /// shows, or the one it opens at.
        var step: String
        /// The step's place, from 1.
        var stepNumber: Int
        /// How many steps the tour has.
        var steps: Int
        /// The step's title on the panel.
        var title: String
        /// The parts of the window the tour rings now: `setupSteps`,
        /// `agentStep`, `stage`, `composer`, `send` or `thread`.
        var rings: [String]
        /// Whether the agent answered the send made in the tour.
        var replied: Bool
        /// Whether "Finish setup" shows in the header.
        var finishSetup: Bool
        /// The count on "Finish setup": the setup items not detected yet.
        var setupItemsLeft: Int

        /// `the tour shows step 2 of 5: Connect your agent`.
        var line: String {
            open
                ? "the tour shows step \(stepNumber) of \(steps): \(title)"
                : step == TourStep.tools.rawValue
                    ? "the tour is closed; Finish setup or havooch tour show starts it"
                    : "the tour is closed at step \(stepNumber) of \(steps); havooch tour show opens it there"
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
    /// What Havooch detects of the setup, and the skill install; the app's
    /// model fills it in.
    var setup: Setup?
    /// The settings file and the verdict of its last reload; the app's
    /// model fills it in.
    var config: Config?
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
    /// The setup tour; the app's model fills it in.
    var tour: Tour?
    /// The open video's threads: General first, then in time order.
    var threads: [Thread]
    /// The ids of the messages waiting to be sent, in the threads' order.
    var queue: [String]
    /// The open video's sends, in the order they were sent.
    var sends: [Send]
    /// The recent videos of this run's data folder, the newest first; the
    /// app's model fills it in.
    var recents: [Recent] = []
    /// What the window shows; the app's model fills it in.
    var screen: Screen = .home
    /// The window this report is of: its id; `null` with no window open.
    var window: String?
    /// Every window, in the order they were made.
    var windows: [Window] = []

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
        case app, screen, lease, listener, video, player, popover, threads, queue, sends
        case transcript, theme, config, sidebar, tour, recents, setup, window, windows
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(app, forKey: .app)
        try container.encode(window, forKey: .window)
        try container.encode(windows, forKey: .windows)
        try container.encode(screen, forKey: .screen)
        try container.encode(lease, forKey: .lease)
        try container.encode(listener, forKey: .listener)
        try container.encode(theme, forKey: .theme)
        try container.encode(setup, forKey: .setup)
        try container.encode(config, forKey: .config)
        try container.encode(video, forKey: .video)
        try container.encode(player, forKey: .player)
        try container.encode(transcript, forKey: .transcript)
        try container.encode(popover, forKey: .popover)
        try container.encode(sidebar, forKey: .sidebar)
        try container.encode(tour, forKey: .tour)
        try container.encode(threads, forKey: .threads)
        try container.encode(queue, forKey: .queue)
        try container.encode(sends, forKey: .sends)
        try container.encode(recents, forKey: .recents)
    }

    // MARK: - state

    /// `state --json`.
    var json: String { Self.json(self) }

    /// `state`.
    var lines: String {
        """
        \(AppIdentity.appName) \(app.version), \(app.demo ? "demo data" : "your data") in \(app.support)
        window: \(window ?? "none")
        screen: \(screen.rawValue)
        video: \(video.map { "\($0.title) (\(TimeCode.text($0.duration))) \($0.path)" } ?? "none")
        player: \(player.playing ? "playing" : "paused") at \(TimeCode.text(player.time))
        transcript: \(transcript?.line ?? "none")
        \(leaseLine)
        \(listenerLine)
        \(theme.map { $0.line + "\n" } ?? "")\(config.map { $0.lines + "\n" } ?? "")\(setup.map { $0.line + "\n" } ?? "")threads: \(threadLines)
        recents: \(recentLines)
        \(Self.windowLines(windows))
        """
    }

    /// `window list`, and the end of `state`: `windows: 2`, then one line
    /// per window.
    static func windowLines(_ windows: [Window]) -> String {
        (["windows: \(windows.count)"] + windows.map { "  " + $0.line }).joined(separator: "\n") + "\n"
    }

    /// The recent videos, one line each: `sample at 0:12, 2026-10-06T…, /videos/sample.mp4`.
    private var recentLines: String {
        let lines = recents.map { recent in
            let gone = recent.available ? "" : " unavailable"
            return "  \(recent.title) at \(TimeCode.text(recent.position)), "
                + "\(recent.openedAt.formatted(.iso8601))\(gone) \(recent.path)"
        }
        return ([String(recents.count)] + lines).joined(separator: "\n")
    }

    /// `listener: listening (Claude Code), 0 sends waiting, 1 taken`.
    private var listenerLine: String {
        let who = listener.session.map { " (\($0)" + (listener.tookOverFrom.map { ", took over from \($0)" } ?? "") + ")" } ?? ""
        let waiting = "\(listener.pendingSends) \(listener.pendingSends == 1 ? "send" : "sends") waiting"
        let now = listener.activity.map { "\n  now on \($0.thread): \($0.text.replacing("\n", with: " "))" }.joined()
        return "listener: \(listener.presence)\(who), \(waiting), \(listener.takenSends) taken" + now
    }

    /// The threads, one line each with their messages under them.
    private var threadLines: String {
        let lines = threads.flatMap { thread in
            let place = thread.time.map { "#\(thread.number) at \(TimeCode.text($0))" } ?? "#0 General"
            let head = "  \(place) \(thread.id) \(thread.state ?? "-")\(thread.unread ? " unread" : "")"
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
    fileprivate static func milliseconds(_ seconds: Double) -> Double {
        (seconds * 1000).rounded() / 1000
    }
}
