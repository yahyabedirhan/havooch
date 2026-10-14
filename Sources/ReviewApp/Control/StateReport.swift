import Foundation
import ReviewCore
import ReviewLease
import ReviewStore
import ReviewWire

nonisolated struct StateReport: Encodable, Equatable {
    struct App: Encodable, Equatable {
        var version: String
        var demo: Bool
        var support: String
        var active = false
    }

    enum Screen: String, Encodable, Equatable {
        case home, player, none
    }

    struct Window: Encodable, Equatable {
        var id: String
        var key: Bool
        var onScreen: Bool
        var screen: Screen
        var video: Held?
        var listener: Heard?

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

        struct Held: Encodable, Equatable {
            var path: String
            var title: String
            var contentHash: String
            var project: String? = nil
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
        var contextNote = ""
    }

    struct Popover: Encodable, Equatable {
        var thread: Int?
        var time: Double
        var text: String
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

    struct Version: Encodable, Equatable {
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

    struct Project: Encodable, Equatable {
        var slug: String
        var title: String
        var version: Int?
        var versions: [Version]
        var switcher: Switcher?
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

        var line: String {
            "project: \(slug) \"\(title)\", " + (version.map { "v\($0)" } ?? "a removed version") + " of \(versions.count)"
                + (switcher.map { "\n" + $0.line } ?? "") + (compare.map { "\n" + $0.line } ?? "")
        }
    }

    struct Compare: Encodable, Equatable {
        var phase: String
        var left: Int
        var right: Int
        var layout: String
        var showing: String?
        var slider: Double
        var active: String?
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

    struct Switcher: Encodable, Equatable {
        var segments: [Int]
        var selected: Int?
        var field: String?
        var picker: Picker?

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

    struct HomeProject: Encodable, Equatable {
        var slug: String
        var title: String
        var versions: Int
        var latestPath: String?
        var available: Bool
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

    struct Thread: Encodable, Equatable {
        var id: String
        var number: Int
        var time: Double?
        var version: Version?
        var state: String?
        var keyframePath: String?
        var popoverFrame: PopoverFrame?
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

    struct Message: Encodable, Equatable {
        var id: String
        var author: String
        var kind: String
        var text: String
        var at: Date
        var state: String?
        var region: Region?
        var cropPath: String?
        var sendId: String?
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

    struct Send: Encodable, Equatable {
        var id: String
        var sentAt: Date
        var messageIds: [String]
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

    struct Listener: Encodable, Equatable {
        var presence: String
        var waitOpen: Bool
        var session: String?
        var pendingSends: Int
        var takenSends: Int
        var activity: [Activity] = []
        var tookOverFrom: String?

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

    struct Activity: Encodable, Equatable {
        var thread: String
        var message: String
        var text: String
    }

    struct Player: Encodable, Equatable {
        var time: Double
        var playing: Bool
    }

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

        @MainActor
        init(_ sound: ReviewApp.Sound, panelOpen: Bool) {
            self.init(
                volume: Int((sound.level * 100).rounded()), muted: sound.isMuted, mutedForCheck: sound.isMutedForCheck,
                panelOpen: panelOpen
            )
        }

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

    struct Recent: Encodable, Equatable {
        var path: String
        var title: String
        var contentHash: String
        var openedAt: Date
        var position: Double
        var available: Bool

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

    struct Transcript: Encodable, Equatable {
        var source: String
        var complete: Bool
        var lines: Int
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

        var line: String {
            let progress = problem.map { "stopped: \($0)" } ?? (complete ? "complete" : "transcribing")
            return "\(source), \(lines) \(lines == 1 ? "line" : "lines"), \(progress)"
        }
    }

    struct Sidebar: Encodable, Equatable {
        var thread: String?
        var width: Double
        var composer: Composer? = nil
        var mode = "threads"
        var connect: Connect? = nil
        var versions: Versions? = nil

        struct Versions: Encodable, Equatable {
            var sections: [Int]
            var removedSection: Bool
            var onScreen: Int?
            var picked: [Int]
            var showing: String
            var older: [Int]
            var stillOpen: [String]
            var menu: Menu?

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

        struct Connect: Encodable, Equatable {
            var reason: String
            var phase: String
            var harness: String
            var readiness: String
            var prompt: String?
            var banner: Banner? = nil
            var listener: Card? = nil

            struct Banner: Encodable, Equatable {
                var kind: String
                var messages: Int
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

            struct Card: Encodable, Equatable {
                var agent: String
                var place: String
                var since: Date?
                var reconnectingUntil: Date? = nil
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

        struct Composer: Encodable, Equatable {
            var target: String
            var kind: String
            var thread: String?
            var number: Int
            var time: Double?
            var general: Bool
            var text: String
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

    struct Tour: Encodable, Equatable {
        var open: Bool
        var step: String
        var stepNumber: Int
        var steps: Int
        var title: String
        var rings: [String]
        var replied: Bool
        var finishSetup: Bool
        var setupItemsLeft: Int

        var line: String {
            open
                ? "the tour shows step \(stepNumber) of \(steps): \(title)"
                : step == TourStep.tools.rawValue
                    ? "the tour is closed; Finish setup or havooch tour open starts it"
                    : "the tour is closed at step \(stepNumber) of \(steps); havooch tour open opens it there"
        }
    }

    var app: App
    var lease: ControlLease.Status?
    var listener = Listener.absent
    var theme: Theme?
    var setup: Setup?
    var firstRun: FirstRun?
    var config: Config?
    var video: Video?
    var project: Project?
    var projects: [HomeProject] = []
    var player: Player
    var sound: Sound?
    var transcript: Transcript?
    var popover: Popover?
    var sidebar: Sidebar?
    var tour: Tour?
    var threads: [Thread]
    var queue: [String]
    var sends: [Send]
    var recents: [Recent] = []
    var screen: Screen = .home
    var window: String?
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

    var json: String { Self.json(self) }

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

    static func windowLines(_ windows: [Window]) -> String {
        (["windows: \(windows.count)"] + windows.map { "  " + $0.line }).joined(separator: "\n") + "\n"
    }

    private var recentLines: String {
        let lines = recents.map { recent in
            let gone = recent.available ? "" : " unavailable"
            return "  \(recent.title) at \(TimeCode.text(recent.position)), "
                + "\(recent.openedAt.formatted(.iso8601))\(gone) \(recent.path)"
        }
        return ([String(recents.count)] + lines).joined(separator: "\n")
    }

    private var projectLines: String {
        let lines = projects.map { "  \($0.slug) \"\($0.title)\", \($0.versions) version\($0.versions == 1 ? "" : "s")" }
        return ([String(projects.count)] + lines).joined(separator: "\n")
    }

    private var listenerLine: String {
        let who = listener.session.map { " (\($0)" + (listener.tookOverFrom.map { ", took over from \($0)" } ?? "") + ")" } ?? ""
        let waiting = "\(listener.pendingSends) \(listener.pendingSends == 1 ? "send" : "sends") waiting"
        let now = listener.activity.map { "\n  now on \($0.thread): \($0.text.replacing("\n", with: " "))" }.joined()
        return "listener: \(listener.presence)\(who), \(waiting), \(listener.takenSends) taken" + now
    }

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

    var statusJSON: String {
        Self.json(Status(
            running: true, version: app.version, demo: app.demo, support: app.support,
            video: video?.path, lease: lease
        ))
    }

    var statusLines: String {
        """
        running: \(AppIdentity.appName) \(app.version)
        data: \(app.demo ? "demo" : "yours"), \(app.support)
        video: \(video?.path ?? "none")
        \(leaseLine)

        """
    }

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

    static func json(_ value: some Encodable) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return String(decoding: try! encoder.encode(value), as: UTF8.self) + "\n"
    }

    fileprivate static func milliseconds(_ seconds: Double) -> Double {
        (seconds * 1000).rounded() / 1000
    }
}
