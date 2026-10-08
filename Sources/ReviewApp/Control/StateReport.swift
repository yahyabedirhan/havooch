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

        /// The video a window holds, and its project's slug and the
        /// version's number in a project.
        struct Held: Encodable, Equatable {
            var path: String
            var title: String
            var contentHash: String
            /// The project's slug; `null` for a plain video.
            var project: String? = nil
            /// The number of the version on screen; `null` for a plain
            /// video, and for a path that left the project's list.
            var version: Int? = nil

            func encode(to encoder: any Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(path, forKey: .path)
                try container.encode(title, forKey: .title)
                try container.encode(contentHash, forKey: .contentHash)
                try container.encode(project, forKey: .project)
                try container.encode(version, forKey: .version)
            }

            private enum CodingKeys: String, CodingKey {
                case path, title, contentHash, project, version
            }
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

        /// `w1 key player cut1.mp4 /Movies/cut1.mp4`, `w3 player launch-video v2
        /// cut2.mp4 /Movies/cut2.mp4`, or `w2 home off screen`.
        var line: String {
            let project = video?.project.map { project in " \(project) " + (video?.version.map { "v\($0)" } ?? "removed version") } ?? ""
            let held = video.map { "\(project) \($0.title) \($0.path)" } ?? ""
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

    /// A version of a project: its number (from 1), its file and its label.
    struct Version: Encodable, Equatable {
        /// `null` for a version whose path left the project's list.
        var number: Int?
        var path: String
        var label: String?

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(number, forKey: .number)
            try container.encode(path, forKey: .path)
            try container.encode(label, forKey: .label)
        }

        private enum CodingKeys: String, CodingKey {
            case number, path, label
        }
    }

    /// The project a window holds (ADR 0004): its slug and title, the
    /// version on screen, and every version in order.
    struct Project: Encodable, Equatable {
        var slug: String
        var title: String
        /// The number of the version on screen; `null` when its path has
        /// left the list.
        var version: Int?
        var versions: [Version]
        /// The header's version switcher (E10), in a window's `state`;
        /// left out elsewhere, such as in `project new`'s answer.
        var switcher: Switcher?
        /// The comparison (E11), in a window's `state`, where it is `null`
        /// while Compare is closed; left out with the switcher elsewhere.
        var compare: Compare?

        init(_ outline: ProjectOutline, onScreen path: String?) {
            slug = outline.slug
            title = outline.title
            version = path.flatMap(outline.number(of:))
            versions = outline.versions.enumerated().map { Version(number: $0.offset + 1, path: $0.element.path, label: $0.element.label) }
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(slug, forKey: .slug)
            try container.encode(title, forKey: .title)
            try container.encode(version, forKey: .version)
            try container.encode(versions, forKey: .versions)
            try container.encodeIfPresent(switcher, forKey: .switcher)
            if switcher != nil { try container.encode(compare, forKey: .compare) }
        }

        private enum CodingKeys: String, CodingKey {
            case slug, title, version, versions, switcher, compare
        }

        /// `project: launch-video "Launch video", v2 of 2`, then the
        /// switcher's line when there is one.
        var line: String {
            "project: \(slug) \"\(title)\", " + (version.map { "v\($0)" } ?? "a removed version") + " of \(versions.count)"
                + (switcher.map { "\n" + $0.line } ?? "") + (compare.map { "\n" + $0.line } ?? "")
        }
    }

    /// The comparison of two versions in a project's window (E11,
    /// compare-control V4): the popover's choice while it is open, or what
    /// the window compares.
    struct Compare: Encodable, Equatable {
        /// `choosing` while the popover is open, `comparing` once the window
        /// compares.
        var phase: String
        /// The versions on the left and on the right, from 1.
        var left: Int
        var right: Int
        /// `side-by-side`, `flip` or `slider`.
        var layout: String
        /// In Flip, the side showing; `null` in the other layouts.
        var showing: String?
        /// How much of the picture's width shows the left side in Slider.
        var slider: Double
        /// While comparing, the side new messages go to (L63); `null` in the
        /// popover.
        var active: String?
        /// A side's version picker open in the popover; `null` while none is.
        var picker: Picker?

        struct Picker: Encodable, Equatable {
            var side: String
            var query: String
            var matches: [Int]
            var highlighted: Int?

            func encode(to encoder: any Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(side, forKey: .side)
                try container.encode(query, forKey: .query)
                try container.encode(matches, forKey: .matches)
                try container.encode(highlighted, forKey: .highlighted)
            }

            private enum CodingKeys: String, CodingKey {
                case side, query, matches, highlighted
            }
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(phase, forKey: .phase)
            try container.encode(left, forKey: .left)
            try container.encode(right, forKey: .right)
            try container.encode(layout, forKey: .layout)
            try container.encode(showing, forKey: .showing)
            try container.encode(slider, forKey: .slider)
            try container.encode(active, forKey: .active)
            try container.encode(picker, forKey: .picker)
        }

        private enum CodingKeys: String, CodingKey {
            case phase, left, right, layout, showing, slider, active, picker
        }

        /// `compare: popover, v1 on the left and v2 on the right, side by
        /// side`, or while comparing `compare: v1 on the left and v2 on the
        /// right, flip showing the left, messages go to v1 on the left`, then
        /// an open picker: `  picker left "alt": 1 match, v3 highlighted`.
        var line: String {
            let sides = "v\(left) on the left and v\(right) on the right"
            let how: String
            switch layout {
            case CompareLayout.flip.rawValue: how = "flip" + (showing.map { " showing the \($0)" } ?? "")
            case CompareLayout.slider.rawValue: how = "slider at \(Int((slider * 100).rounded()))%"
            default: how = "side by side"
            }
            let target = active.map { side in ", messages go to v\(side == "left" ? left : right) on the \(side)" } ?? ""
            let open = picker.map { picker in
                "\n  picker \(picker.side) \"\(picker.query)\": \(picker.matches.count) match\(picker.matches.count == 1 ? "" : "es")"
                    + (picker.highlighted.map { ", v\($0) highlighted" } ?? "")
            } ?? ""
            return "compare: " + (phase == "choosing" ? "popover, " : "") + "\(sides), \(how)\(target)\(open)"
        }
    }

    /// The version switcher of a project's window (E10, version-switcher
    /// V5): the versions shown as segments, the one on screen, the field
    /// for the older ones and the picker it opens.
    struct Switcher: Encodable, Equatable {
        /// The numbers of the last three versions, oldest first.
        var segments: [Int]
        /// The number of the version on screen; `null` for a removed one.
        var selected: Int?
        /// The field's words, `All 50` or the older version on screen
        /// (`v12`); `null` for a project of three versions or fewer.
        var field: String?
        /// The picker under the field; `null` while it is closed.
        var picker: Picker?

        /// The open picker: what is typed in its search field, its rows,
        /// newest first, and the one Return opens.
        struct Picker: Encodable, Equatable {
            var query: String
            var matches: [Int]
            var highlighted: Int?

            func encode(to encoder: any Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(query, forKey: .query)
                try container.encode(matches, forKey: .matches)
                try container.encode(highlighted, forKey: .highlighted)
            }

            private enum CodingKeys: String, CodingKey {
                case query, matches, highlighted
            }
        }

        init(_ versions: VersionSwitch, picker: VersionPicker?) {
            segments = versions.recent.map(\.number)
            selected = versions.current
            field = versions.field
            self.picker = picker.map { picker in
                let matches = versions.matches(picker.query)
                return Picker(query: picker.query, matches: matches.map(\.number), highlighted: picker.highlight(in: matches))
            }
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(segments, forKey: .segments)
            try container.encode(selected, forKey: .selected)
            try container.encode(field, forKey: .field)
            try container.encode(picker, forKey: .picker)
        }

        private enum CodingKeys: String, CodingKey {
            case segments, selected, field, picker
        }

        /// `switcher: v48 [v49] v50, All 50`, then the open picker:
        /// `  picker "4": 5 matches, v49 highlighted`.
        var line: String {
            let marks = segments.map { $0 == selected ? "[v\($0)]" : "v\($0)" }.joined(separator: " ")
            let shownField = field.map { selected != nil && !segments.contains(selected ?? 0) ? ", [\($0)]" : ", \($0)" } ?? ""
            let open = picker.map { picker in
                "\n  picker \"\(picker.query)\": \(picker.matches.count) match\(picker.matches.count == 1 ? "" : "es")"
                    + (picker.highlighted.map { ", v\($0) highlighted" } ?? "")
            } ?? ""
            return "switcher: \(marks)\(shownField)\(open)"
        }
    }

    /// One project on the home screen (story 48): its title, its latest
    /// version and when the person last opened it.
    struct HomeProject: Encodable, Equatable {
        var slug: String
        var title: String
        /// How many versions it lists.
        var versions: Int
        /// The latest version's file; `null` with no version.
        var latestPath: String?
        /// Whether the latest version's file is there now.
        var available: Bool
        /// When the person last opened it; `null` before they did.
        var openedAt: Date?

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(slug, forKey: .slug)
            try container.encode(title, forKey: .title)
            try container.encode(versions, forKey: .versions)
            try container.encode(latestPath, forKey: .latestPath)
            try container.encode(available, forKey: .available)
            try container.encode(openedAt, forKey: .openedAt)
        }

        private enum CodingKeys: String, CodingKey {
            case slug, title, versions, latestPath, available, openedAt
        }
    }

    /// One thread: its number, its frame and keyframe, its state and its
    /// messages in the order written.
    struct Thread: Encodable, Equatable {
        var id: String
        var number: Int
        /// The frame time; `null` for General.
        var time: Double?
        /// In a project, the version the thread was raised on, tagged with
        /// its number as the list is now (`null` for a removed version);
        /// `null` on a plain video and for General.
        var version: Version?
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
            try container.encode(version, forKey: .version)
            try container.encode(state, forKey: .state)
            try container.encode(keyframePath, forKey: .keyframePath)
            try container.encode(popoverFrame, forKey: .popoverFrame)
            try container.encode(unread, forKey: .unread)
            try container.encode(messages, forKey: .messages)
        }

        private enum CodingKeys: String, CodingKey {
            case id, number, time, version, state, keyframePath, popoverFrame, unread, messages
        }

        /// `thread` of the review `review`, whose pictures are where
        /// `layout` says; in a project, `project` tags its version.
        init(_ thread: ReviewThread, review: ReviewKey, layout: SupportLayout, project: ProjectOutline? = nil) {
            id = thread.id.text
            number = thread.number
            time = thread.time
            version = thread.anchor.map { anchor in
                let number = project?.number(of: anchor.path)
                return Version(number: number, path: anchor.path, label: number.flatMap { project?.version($0)?.label })
            }
            state = thread.state?.rawValue
            keyframePath = layout.keyframe(of: thread, on: review)?.path
            popoverFrame = thread.popoverFrame
            unread = thread.isUnread
            messages = thread.messages.map { Message($0, review: review, layout: layout) }
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

        init(_ message: ReviewCore.Message, review: ReviewKey, layout: SupportLayout) {
            id = message.id.text
            author = message.author.rawValue
            kind = message.kind.rawValue
            text = message.text
            at = message.at
            state = message.state?.rawValue
            region = message.region
            cropPath = layout.crop(of: message, on: review)?.path
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

        init(_ send: ReviewCore.Send, in review: Review) {
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

    /// The sound, the same in every window: `volume` is the level from 0
    /// to 100, where 0 is muted; `muted` is whether nothing plays, also in
    /// a run muted for an agent's check (`mutedForCheck`, started with
    /// `HAVOOCH_MUTED=1`), whatever its level. `panelOpen` is whether the
    /// window's sound panel is open over the stage.
    struct Sound: Encodable, Equatable {
        var volume: Int
        var muted: Bool
        var mutedForCheck: Bool
        var panelOpen: Bool

        init(volume: Int, muted: Bool, mutedForCheck: Bool = false, panelOpen: Bool = false) {
            self.volume = volume
            self.muted = muted
            self.mutedForCheck = mutedForCheck
            self.panelOpen = panelOpen
        }

        /// `sound` as it is now, with a window's panel.
        @MainActor
        init(_ sound: ReviewApp.Sound, panelOpen: Bool) {
            self.init(
                volume: Int((sound.level * 100).rounded()), muted: sound.isMuted, mutedForCheck: sound.isMutedForCheck,
                panelOpen: panelOpen
            )
        }

        /// `sound: 70%`, `sound: muted`, or `sound: muted for an agent
        /// check (HAVOOCH_MUTED=1), level 70%`, with `, panel open`.
        var line: String {
            let level: String
            if mutedForCheck {
                level = "muted for an agent check (HAVOOCH_MUTED=1), level \(volume)%"
            } else {
                level = muted ? "muted" : "\(volume)%"
            }
            return "sound: \(level)\(panelOpen ? ", panel open" : "")"
        }
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
        /// A project's thread list by version (E9); `null` on a plain
        /// video, whose list is by group.
        var versions: Versions? = nil

        /// A project's thread list by version: its sections, the versions
        /// with none, their open threads, and "All versions".
        struct Versions: Encodable, Equatable {
            /// The version sections in the list's order, by number: the last
            /// three newest first, then an older one on screen, then each
            /// picked one, the latest pick first.
            var sections: [Int]
            /// Whether a section holds threads of removed versions.
            var removedSection: Bool
            /// The number of the version on screen, marked in the list;
            /// `null` for a removed version.
            var onScreen: Int?
            /// The versions picked from All versions, each with a close button.
            var picked: [Int]
            /// `Showing v48 to v50, v12`.
            var showing: String
            /// The versions with no section, newest first.
            var older: [Int]
            /// The ids of the open threads on those versions: the footer's chips.
            var stillOpen: [String]
            /// All versions while it shows; `null` while it is closed.
            var menu: Menu?

            /// All versions: its search and its three groups, by number.
            struct Menu: Encodable, Equatable {
                var search: String
                var inList: [Int]
                var stillOpen: [Int]
                var older: [Int]
            }

            init(_ tree: VersionTree, menu: AllVersionsMenu?, search: String?) {
                sections = tree.shown
                removedSection = tree.sections.contains { $0.kind == .removed }
                onScreen = tree.sections.first(where: \.isOnScreen)?.number
                picked = tree.sections.filter(\.isPicked).compactMap(\.number)
                showing = tree.showing
                older = tree.older
                stillOpen = tree.stillOpen.map(\.id.text)
                self.menu = menu.map {
                    Menu(
                        search: search ?? "", inList: $0.inList.map(\.number), stillOpen: $0.stillOpen.map(\.number),
                        older: $0.older.map(\.number)
                    )
                }
            }

            func encode(to encoder: any Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(sections, forKey: .sections)
                try container.encode(removedSection, forKey: .removedSection)
                try container.encode(onScreen, forKey: .onScreen)
                try container.encode(picked, forKey: .picked)
                try container.encode(showing, forKey: .showing)
                try container.encode(older, forKey: .older)
                try container.encode(stillOpen, forKey: .stillOpen)
                try container.encode(menu, forKey: .menu)
            }

            private enum CodingKeys: String, CodingKey {
                case sections, removedSection, onScreen, picked, showing, older, stillOpen, menu
            }
        }

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
            try container.encode(versions, forKey: .versions)
        }

        private enum CodingKeys: String, CodingKey {
            case mode, thread, width, composer, connect, versions
        }
    }

    /// The setup tour over the stage, and "Finish setup" in the header (H4,
    /// L58).
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
    /// The first-run window: whether it shows, its step and its demo
    /// prompt; the app's model fills it in.
    var firstRun: FirstRun?
    /// The settings file and the verdict of its last reload; the app's
    /// model fills it in.
    var config: Config?
    /// The open video; `null` with none.
    var video: Video?
    /// The project the window holds, with the version on screen; `null`
    /// for a plain video and with none. The app's model fills it in.
    var project: Project?
    /// The projects in `config.toml`, the most recently opened first, as
    /// the home screen shows them; the app's model fills it in.
    var projects: [HomeProject] = []
    var player: Player
    /// The sound, the app's; the app's model fills it in.
    var sound: Sound?
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
        case app, screen, lease, listener, video, player, sound, popover, threads, queue, sends
        case transcript, theme, config, sidebar, tour, recents, setup, window, windows, project, projects, firstRun
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
        try container.encode(firstRun, forKey: .firstRun)
        try container.encode(config, forKey: .config)
        try container.encode(video, forKey: .video)
        try container.encode(project, forKey: .project)
        try container.encode(player, forKey: .player)
        try container.encode(sound, forKey: .sound)
        try container.encode(transcript, forKey: .transcript)
        try container.encode(popover, forKey: .popover)
        try container.encode(sidebar, forKey: .sidebar)
        try container.encode(tour, forKey: .tour)
        try container.encode(threads, forKey: .threads)
        try container.encode(queue, forKey: .queue)
        try container.encode(sends, forKey: .sends)
        try container.encode(recents, forKey: .recents)
        try container.encode(projects, forKey: .projects)
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
        \(project.map { $0.line + "\n" } ?? "")player: \(player.playing ? "playing" : "paused") at \(TimeCode.text(player.time))
        \(sound.map { $0.line + "\n" } ?? "")transcript: \(transcript?.line ?? "none")
        \(leaseLine)
        \(listenerLine)
        \(theme.map { $0.line + "\n" } ?? "")\(config.map { $0.lines + "\n" } ?? "")\(setup.map { $0.line + "\n" } ?? "")\(firstRun.map { $0.line + "\n" } ?? "")threads: \(threadLines)
        recents: \(recentLines)
        projects: \(projectLines)
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

    /// The home screen's projects, one line each: `launch-video "Launch video", 2 versions`.
    private var projectLines: String {
        let lines = projects.map { "  \($0.slug) \"\($0.title)\", \($0.versions) version\($0.versions == 1 ? "" : "s")" }
        return ([String(projects.count)] + lines).joined(separator: "\n")
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
            let version = thread.version.map { $0.number.map { " v\($0)" } ?? " removed version" } ?? ""
            let head = "  \(place)\(version) \(thread.id) \(thread.state ?? "-")\(thread.unread ? " unread" : "")"
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
