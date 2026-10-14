import AppKit
import AVFoundation
import Observation
import ReviewCore
import ReviewLease
import ReviewSetup
import ReviewStore
import ReviewTranscript
import ReviewWire
import UniformTypeIdentifiers

@Observable
final class WindowModel: WindowControlling {
    struct OpenVideo: Equatable {
        var url: URL
        var title: String
        var contentHash: String
    }

    struct Problem: Equatable {
        var title: String
        var reason: String
    }

    let app: AppModel
    let id: String
    private(set) var engine: PlayerEngine
    @ObservationIgnored weak var nsWindow: NSWindow?
    var data: DataFolder { app.data }
    var desk: ReviewDesk { data.desk }
    var reviewKey: ReviewKey? {
        guard let video else { return nil }
        return project.map { .project(slug: $0) } ?? .video(contentHash: video.contentHash)
    }
    var listener: ListenerQueue? { reviewKey.map(data.listeners.queue(for:)) }
    var transcripts: TranscriptDesk { data.transcripts }
    var themes: ThemeDesk { app.themes }
    var config: ConfigDesk { app.config }
    var support: URL { data.support }
    var isInAppDemo: Bool { app.isInAppDemo }
    var isDemo: Bool { app.isDemo }
    private(set) var video: OpenVideo?
    private(set) var project: String? {
        didSet {
            guard project != oldValue else { return }
            pickedVersions = []
            versionMenu = nil
        }
    }
    var review: Review? { reviewKey.flatMap(desk.opened) }
    var target: WindowTarget? {
        guard let video else { return nil }
        return project.map { .project(slug: $0) } ?? .video(contentHash: video.contentHash, path: video.url.path)
    }
    var projectOutline: ProjectOutline? { project.flatMap(app.config.outline) }
    var onScreen: VersionAnchor? {
        guard project != nil, let video else { return nil }
        return VersionAnchor(path: video.url.path)
    }
    var versionNumber: Int? {
        guard let onScreen else { return nil }
        return projectOutline?.number(of: onScreen.path)
    }

    var projectWords: HeaderWords.Project? {
        guard let project else { return nil }
        let title = projectOutline?.title ?? project
        if let compare, isComparing {
            return HeaderWords.Project(title: title, version: "Comparing v\(compare.number(.left)) and v\(compare.number(.right))")
        }
        return HeaderWords.Project(title: title, version: versionSwitch?.onScreen?.line ?? "a removed version")
    }

    var versionSwitch: VersionSwitch? {
        guard let outline = projectOutline else { return nil }
        let now = Date()
        let entries = outline.versions.enumerated().map { index, version in
            VersionSwitch.Entry(
                number: index + 1, label: version.label,
                threads: threads.count { !$0.isGeneral && $0.anchor?.path == version.path },
                made: Self.madeDate(of: version.path).map { VersionSwitch.made($0, now: now) }
            )
        }
        return VersionSwitch(versions: entries, current: versionNumber)
    }

    private static func madeDate(of path: String) -> Date? {
        let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        return attributes?[.creationDate] as? Date ?? attributes?[.modificationDate] as? Date
    }

    private(set) var versionPicker: VersionPicker?

    func versionTag(of thread: ReviewThread) -> VersionTag? {
        guard let anchor = thread.anchor else { return nil }
        return projectOutline?.tag(anchor) ?? .removed
    }
    var draft: Draft?
    private(set) var selection: ThreadID?
    private(set) var shown: ThreadID? {
        didSet {
            guard let shown else { return }
            markSeen(shown)
            connect = nil
        }
    }
    var connect: ConnectEntry?
    var pickedHarness: Harness?
    var tour = TourState()
    @ObservationIgnored private var focusedControls: [(id: UUID, press: () -> Void)] = []
    private(set) var isDrawingRegion = false
    var isSidebarVisible = true
    var isContextShown = false
    private(set) var sidecar: ContextReader.Sidecar?
    var problem: Problem?
    private(set) var notices: [Notice] = []

    private(set) var composerDrafts: [ComposerTarget.DraftKey: String] = [:]
    private(set) var isComposerGeneral = false
    private(set) var drawnRegion: Draft?
    private(set) var composerFocusRequests = 0
    private(set) var isComposing = false

    @ObservationIgnored var stageArea: CGRect = .zero
    var trackArea: CGRect = .zero

    private var layout: SupportLayout { data.layout }
    @ObservationIgnored private var committing: Task<Void, Never>?
    private var commitsUnderWay = 0
    @ObservationIgnored private var isSending = false

    init(app: AppModel, id: String) {
        self.app = app
        self.id = id
        engine = PlayerEngine(sound: app.sound)
    }

    var transcript: StateReport.Transcript? {
        video.flatMap { transcripts.report(of: $0.contentHash) }
    }

    var threads: [ReviewThread] { review?.threads ?? [] }

    var frameThreads: [ReviewThread] { threads.filter { !$0.isGeneral && $0.anchor == onScreen } }

    var sends: [Send] { review?.sends ?? [] }

    var canSend: Bool {
        sendCount > 0
    }

    var queuedCount: Int { review?.queue.count ?? 0 }

    var sendCount: Int {
        let popover = draft.map { Self.hasWords($0.text) } == true ? 1 : 0
        let composer = composerTarget.map { !$0.answers && Self.hasWords(composerText) } == true ? 1 : 0
        return (review?.queue.count ?? 0) + commitsUnderWay + popover + composer
    }

    func open(_ url: URL, project: String?) async throws(AppRefusal) {
        try await open(url, resolving: false, project: project)
    }

    func open(_ url: URL) async throws(AppRefusal) {
        try await open(url, resolving: true, project: nil)
    }

    private func open(_ url: URL, resolving: Bool, project: String?) async throws(AppRefusal) {
        let data = app.data
        let url = url.standardizedFileURL
        try AppModel.needFile(url)
        guard let contentHash = await Self.contentHash(of: url, in: app.hashes) else {
            throw AppRefusal("can't read \(url.path)")
        }
        let project = resolving ? try app.resolveTarget(url, contentHash: contentHash, project: nil).reviewKey.slug : project
        let key: ReviewKey = project.map { .project(slug: $0) } ?? .video(contentHash: contentHash)
        try needOwn(key, url)
        let title = url.lastPathComponent
        closePopover(.momentChanged)
        await committing?.value
        if isComparing { exitCompare() }
        try needData(data, for: url)
        let found = try data.desk.review(for: VideoInfo(contentHash: contentHash, title: title, duration: 0, path: url.path), in: key)
        savePosition()
        let closesBefore = closes
        loads += 1
        do {
            try await engine.load(url)
        } catch {
            loads -= 1
            throw error
        }
        loads -= 1
        guard app.data.support == data.support, closes == closesBefore else {
            if video == nil { engine.close() }
            try needData(data, for: url)
            throw AppRefusal("\(url.path) didn't open: the video was closed meanwhile")
        }
        do throws(AppRefusal) {
            try needOwn(key, url)
        } catch {
            if video == nil { engine.close() }
            throw error
        }
        var review = data.desk.review(of: key) ?? found
        let sameReview = reviewKey == key
        let otherVersion = sameReview && project != nil && video?.url != url
        video = OpenVideo(url: url, title: title, contentHash: contentHash)
        self.project = project
        let kept = sameReview ? notices : []
        forgetVideoViews(keepingReview: otherVersion)
        notices = kept
        sidecar = ContextReader.sidecar(beside: url)
        let frameRate = 1 / engine.frameDuration
        review.show(VideoInfo(
            contentHash: contentHash, title: title, duration: engine.duration, path: url.path, frameRate: frameRate
        ))
        desk.open(review)
        if let project {
            desk.library.recordProjectOpened(project, at: Date())
        } else {
            desk.library.recordOpened(url, contentHash: contentHash, at: Date())
        }
        app.refreshRecents()
        app.markFirstRunDone()
        transcripts.opened(VideoFile(url: url, contentHash: contentHash, frameRate: frameRate, duration: engine.duration))
    }

    private func needOwn(_ key: ReviewKey, _ url: URL) throws(AppRefusal) {
        guard let holder = app.windows.holding(key), holder !== self else { return }
        switch key {
        case .video:
            throw AppRefusal("\(url.lastPathComponent) is open in window \(holder.id); one video opens in one window")
        case .project(let slug):
            throw AppRefusal("the project \(slug) is open in window \(holder.id); one project opens in one window")
        }
    }

    func moveIntoProject(_ slug: String) {
        guard video != nil, project == nil else { return }
        project = slug
    }

    func showVersion(_ number: Int, of slug: String) async throws(AppRefusal) {
        guard let outline = app.config.outline(slug) else { throw AppRefusal("no project `\(slug)` in config.toml") }
        guard let version = outline.version(number) else {
            throw AppRefusal("the project \(slug) has no v\(number); it has v1 to v\(outline.versions.count)")
        }
        try await open(URL(fileURLWithPath: version.path), project: slug)
    }

    func switchVersion(to number: Int) async throws(AppRefusal) {
        try needVideo()
        guard let project else {
            throw AppRefusal("this window holds a plain video, which has no versions; `project new` makes it a project")
        }
        versionPicker = nil
        if let side = compare?.side(of: number), isComparing {
            activate(side)
            return
        }
        guard number != versionNumber else { return }
        let time = engine.time
        let wasPlaying = isPlaying
        try await showVersion(number, of: project)
        await seekPlayers(to: min(time, engine.duration))
        if wasPlaying { playPlayers() }
    }

    func showVersionForPerson(_ number: Int) {
        Task {
            do throws(AppRefusal) {
                try await switchVersion(to: number)
            } catch {
                problem = Problem(title: "The version didn't open", reason: error.reason)
            }
        }
    }

    func openVersionPicker(query: String = "") throws(AppRefusal) -> VersionSwitch {
        try needVideo()
        guard project != nil, let versions = versionSwitch else {
            throw AppRefusal("this window holds a plain video, which has no versions; `project new` makes it a project")
        }
        guard versions.hasOlder else {
            throw AppRefusal(
                "the project has \(versions.versions.count) version\(versions.versions.count == 1 ? "" : "s"), "
                    + "each one a segment; the picker is for a project of more than \(VersionSwitch.recentCount)"
            )
        }
        versionPicker = VersionPicker(query: query)
        return versions
    }

    func toggleVersionPicker() {
        if versionPicker != nil {
            closeVersionPicker()
        } else {
            _ = try? openVersionPicker()
        }
    }

    @discardableResult
    func closeVersionPicker() -> Bool {
        guard versionPicker != nil else { return false }
        versionPicker = nil
        return true
    }

    func typeVersionQuery(_ query: String) {
        guard versionPicker != nil else { return }
        versionPicker = VersionPicker(query: query)
    }

    func moveVersionHighlight(by steps: Int) {
        guard let picker = versionPicker, let versions = versionSwitch else { return }
        versionPicker = picker.moved(by: steps, in: versions.matches(picker.query))
    }

    func openHighlightedVersion() {
        guard let picker = versionPicker, let versions = versionSwitch,
              let number = picker.highlight(in: versions.matches(picker.query))
        else { return }
        showVersionForPerson(number)
    }

    private func showVersion(of thread: ReviewThread) async -> Bool {
        guard let anchor = thread.anchor, anchor != onScreen else { return true }
        if let companion, anchor.path == companion.url.path, let side = activeSide {
            activate(side.other)
            return true
        }
        guard let project, projectOutline?.number(of: anchor.path) != nil else { return false }
        do throws(AppRefusal) {
            try await open(URL(fileURLWithPath: anchor.path), project: project)
            return true
        } catch {
            problem = Problem(title: "The version didn't open", reason: error.reason)
            return false
        }
    }

    func closed() {
        closePopover(.momentChanged)
        pausePlayers()
        savePosition()
        if isComparing { exitCompare() }
    }

    @concurrent
    nonisolated static func contentHash(of url: URL, in hashes: ContentHashCache) async -> String? {
        hashes.of(url)
    }

    private func needData(_ data: DataFolder, for url: URL) throws(AppRefusal) {
        guard app.data.support == data.support else {
            throw AppRefusal("\(url.path) didn't open: the app switched to the data in \(self.data.support.path) meanwhile")
        }
    }

    private func forgetVideoViews(keepingReview: Bool = false) {
        draft = nil
        isDrawingRegion = false
        drawnRegion = nil
        isContextShown = false
        versionPicker = nil
        guard !keepingReview else { return }
        compare = nil
        selection = nil
        shown = nil
        connect = nil
        composerDrafts = [:]
        isComposerGeneral = false
        notices = []
    }

    func tryDemo() {
        Task {
            do throws(AppRefusal) {
                try await openDemo()
            } catch {
                problem = Problem(title: "The demo didn't open", reason: error.reason)
            }
        }
    }

    func openDemo() async throws(AppRefusal) {
        try await app.openDemo(in: self)
    }

    func goHome() async {
        if isInAppDemo {
            await app.leaveDemo()
        } else {
            await settle()
            leaveData()
        }
        app.refreshRecents()
    }

    func goHomeForPerson() {
        Task { await goHome() }
    }

    func settle() async {
        closePopover(.momentChanged)
        await committing?.value
    }

    func leaveData() {
        savePosition()
        closeVideo()
    }

    private func closeVideo() {
        closes += 1
        if isComparing { exitCompare() }
        engine.close()
        video = nil
        forgetVideoViews()
        sidecar = nil
    }

    var recents: [StateReport.Recent] { app.recents }

    @ObservationIgnored private var loads = 0
    @ObservationIgnored private var closes = 0

    func savePosition() {
        guard let video, project == nil, loads == 0 else { return }
        desk.library.savePosition(engine.time, of: video.contentHash)
        app.refreshRecents()
    }

    func removeRecent(_ contentHash: String) {
        app.removeRecent(contentHash)
    }

    func refreshRecents() {
        app.refreshRecents()
    }

    func openRecent(_ recent: StateReport.Recent) {
        guard recent.available else { return }
        openForPerson(recent.url)
    }

    var homeProjects: [StateReport.HomeProject] { app.homeProjects }

    func openProject(_ slug: String) {
        app.openProject(slug, from: self)
    }

    var thumbnails: Thumbnails { app.thumbnails }

    func resize(width: Int) async throws(AppRefusal) -> Int {
        guard width > 0 else { throw AppRefusal("the window width must be positive") }
        guard let nsWindow else { throw AppRefusal("window `\(id)` is not on screen") }
        let height = nsWindow.contentView?.bounds.height ?? nsWindow.contentRect(forFrameRect: nsWindow.frame).height
        nsWindow.setContentSize(NSSize(width: CGFloat(width), height: height))
        await Task.yield()
        nsWindow.contentView?.layoutSubtreeIfNeeded()
        let actualWidth = nsWindow.frame.width
        return Int(actualWidth.rounded())
    }

    func setSidebarVisible(_ visible: Bool) {
        isSidebarVisible = visible
    }

    func play() throws(AppRefusal) {
        try needVideo()
        closePopover(.momentChanged)
        playPlayers()
    }

    func pause() throws(AppRefusal) {
        try needVideo()
        pausePlayers()
    }

    func seek(to seconds: Double) async throws(AppRefusal) {
        try needVideo()
        try needInside(seconds)
        closePopover(.momentChanged)
        await committing?.value
        await seekPlayers(to: seconds)
    }

    func addMessage(
        text: String, at: Double?, region: Region? = nil, thread ref: String? = nil
    ) async throws(AppRefusal) -> (message: StateReport.Message, thread: StateReport.Thread) {
        try needVideo()
        try needWords(text)
        if let at { try needInside(at) }
        guard let review = review, let key = reviewKey else { throw Self.noVideo }
        var thread: ReviewThread?
        if let ref {
            guard let parsed = ThreadRef(ref) else {
                throw AppRefusal("`\(ref)` isn't a thread; give a thread id (t-…) or a number of the open video, 0 for General")
            }
            do throws(ReviewRefusal) {
                thread = review.thread(try review.threadID(parsed))
            } catch {
                throw AppRefusal(error.line)
            }
        }
        let time = at.map(engine.frameTime(of:)) ?? (thread.map(\.time) ?? engine.frameTime(of: engine.time))
        var trial = review
        do throws(ReviewRefusal) {
            _ = try trial.write(text: text, at: time, region: region, to: thread?.id, on: onScreen, now: Date())
        } catch {
            throw AppRefusal(error.line)
        }
        var onItsFrame = true
        if let thread { onItsFrame = await showVersion(of: thread) }
        if !onItsFrame, region != nil, let thread {
            throw AppRefusal("#\(thread.number) is on a removed version, which has no frame to draw a region on")
        }
        pausePlayers()
        if let time, onItsFrame {
            closePopover(.momentChanged)
            await committing?.value
            await seekPlayers(to: time)
        }
        let written = try await queueMessage(text: text, time: time, region: region, thread: thread?.id)
        return (
            StateReport.Message(written.message, review: key, layout: layout),
            StateReport.Thread(written.thread, review: key, layout: layout, project: projectOutline)
        )
    }

    func editMessage(_ id: String, text: String) throws(AppRefusal) -> StateReport.Message {
        let id = try messageID(id)
        let message = try change { review throws(ReviewRefusal) in try review.edit(id, text: text) }
        return report(message)
    }

    func deleteMessage(_ id: String) throws(AppRefusal) -> StateReport.Message {
        let id = try messageID(id)
        let deleted = try change { review throws(ReviewRefusal) in try review.delete(id) }
        let report = report(deleted.message)
        if let crop = report.cropPath { ImageFiles.remove(URL(fileURLWithPath: crop)) }
        if deleted.removedThread, let key = reviewKey {
            ImageFiles.remove(layout.keyframe(deleted.thread, of: key))
            if selection == deleted.thread { selection = nil }
            if shown == deleted.thread { shown = nil }
        }
        return report
    }

    func movePopover(_ thread: ThreadID, to frame: PopoverFrame?) throws(AppRefusal) {
        try change { review throws(ReviewRefusal) in try review.setPopoverFrame(thread, frame) }
    }

    @discardableResult
    func setContextNote(_ text: String) throws(AppRefusal) -> String {
        let note = text.trimmingCharacters(in: .whitespacesAndNewlines)
        try change { review in review.note = note }
        return note
    }

    func sendQueue() async throws(AppRefusal) -> StateReport.Send {
        try needVideo()
        await committing?.value
        if let draft, Self.hasWords(draft.text), review?.thread(atFrame: draft.time, on: onScreen)?.openQuestion != nil {
            closePopover(.clickOutside)
        } else if let draft, Self.hasWords(draft.text) {
            self.draft = nil
            do throws(AppRefusal) {
                _ = try await queueMessage(text: draft.text, time: draft.time, region: draft.region, thread: nil)
            } catch {
                if self.draft == nil { self.draft = draft }
                throw error
            }
        }
        if Self.hasWords(composerText) {
            _ = try await writeComposer()
        }
        guard let shown = review?.video else { throw Self.noVideo }
        let send = try change { [transcripts, onScreen] review throws(ReviewRefusal) in
            let videos = review
            return try review.send(at: Date(), onScreen: onScreen) { thread in
                let info = thread.anchor.flatMap { videos.video(at: $0.path) } ?? shown
                return thread.time.map { transcripts.lines(around: $0, of: info) } ?? []
            }
        }
        guard let key = reviewKey, let review = review else { throw Self.noVideo }
        let ref = SendRef(sendID: send.id, review: key)
        let listener = data.listeners.queue(for: key)
        listener.enqueue(ref)
        if listener.presence(at: Date()) == .absent { sentWithNoAgent(ref) }
        tourNoticedSend(ref)
        return StateReport.Send(send, in: review)
    }

    func answer(_ thread: String, text: String) throws(AppRefusal) -> (message: StateReport.Message, number: Int) {
        let (id, key) = try desk.threadID(thread, open: reviewKey)
        let message = try desk.change(key) { review throws(ReviewRefusal) in try review.answer(id, text: text, now: Date()) }
        let report = StateReport.Message(message, review: key, layout: layout)
        data.listeners.queue(for: key).answered(id, with: report)
        notices.removeAll { $0.thread == id && $0.kind == .question }
        return (report, id.number)
    }

    func choose(_ thread: String, choice number: Int) throws(AppRefusal) -> (message: StateReport.Message, number: Int) {
        let (id, key) = try desk.threadID(thread, open: reviewKey)
        guard let review = desk.review(of: key) else { throw AppRefusal(ReviewRefusal.unknownID(thread).line) }
        let words: String
        do throws(ReviewRefusal) {
            words = try review.choice(number, on: id)
        } catch {
            throw AppRefusal(error.line)
        }
        return try answer(id.text, text: words)
    }

    func state() -> StateReport {
        let review = self.review
        let outline = projectOutline
        var report = StateReport(
            app: app.appReport,
            video: video.map {
                .init(
                    path: $0.url.path, contentHash: $0.contentHash, title: $0.title, duration: engine.duration,
                    contextNote: contextNote
                )
            },
            player: .init(time: engine.time, playing: isPlaying),
            popover: draft.map { .init(thread: draftThreadNumber, time: $0.time, text: $0.text, region: $0.region) },
            threads: reviewKey.map { key in threads.map { StateReport.Thread($0, review: key, layout: layout, project: outline) } } ?? [],
            queue: review?.queue.map(\.id.text) ?? [],
            sends: review.map { review in sends.map { StateReport.Send($0, in: review) } } ?? []
        )
        report.project = outline.map { StateReport.Project($0, onScreen: video?.url.path) }
        report.project?.switcher = versionSwitch.map { StateReport.Switcher($0, picker: versionPicker) }
        report.project?.compare = compareReport
        report.projects = app.homeProjects
        report.transcript = transcript
        report.listener = listener?.report(at: Date()) ?? .absent
        report.theme = themes.report
        report.setup = app.setupReport(for: self)
        report.firstRun = app.firstRunReport
        report.config = app.config.report
        report.sidebar = sidebarReport
        report.tour = tourReport
        report.sound = soundReport
        report.recents = recents
        report.screen = screen
        report.window = id
        report.windows = app.windowList()
        return report
    }

    var screen: StateReport.Screen {
        StageContent(hasVideo: video != nil, hasRecents: !recents.isEmpty).screen
    }

    func report(isKey: Bool) -> StateReport.Window {
        StateReport.Window(
            id: id, key: isKey, onScreen: nsWindow?.isVisible ?? false, screen: screen,
            video: video.map {
                StateReport.Window.Held(path: $0.url.path, title: $0.title, contentHash: $0.contentHash, project: project, version: versionNumber)
            },
            listener: listener.map { listener in
                let heard = listener.report(at: Date())
                return StateReport.Window.Heard(presence: heard.presence, session: heard.session)
            }
        )
    }

    private func change<Result>(_ change: (inout Review) throws(ReviewRefusal) -> Result) throws(AppRefusal) -> Result {
        guard let key = reviewKey else { throw Self.noVideo }
        return try desk.change(key, change)
    }

    private func queueMessage(
        text: String, time: Double?, region: Region?, thread: ThreadID?, on showing: Showing? = nil
    ) async throws(AppRefusal) -> Review.Written {
        let (desk, layout) = (self.desk, self.layout)
        guard let showing = showing ?? self.showing, let hash = reviewKey, let asset = showing.asset, var trial = review else {
            throw Self.noVideo
        }
        let (video, onScreen) = (showing.video, showing.anchor)
        let planned: Review.Written
        do throws(ReviewRefusal) {
            planned = try trial.write(text: text, at: time, region: region, to: thread, on: onScreen, now: Date())
        } catch {
            throw AppRefusal(error.line)
        }
        let token = UUID().uuidString
        let pendingKeyframe = planned.startedThread ? layout.pendingImage("\(token)-keyframe", of: hash) : nil
        let pendingCrop = region == nil ? nil : layout.pendingImage("\(token)-crop", of: hash)
        if let frame = planned.thread.time, pendingKeyframe != nil || pendingCrop != nil {
            try await FrameGrabber.writeImages(
                of: asset, at: frame, duration: showing.duration, frameDuration: showing.frameDuration,
                keyframe: pendingKeyframe, region: region, crop: pendingCrop
            )
        }
        defer {
            if let pendingKeyframe { ImageFiles.remove(pendingKeyframe) }
            if let pendingCrop { ImageFiles.remove(pendingCrop) }
        }
        guard reviewKey == hash else { throw AppRefusal("another video opened before the message was queued") }
        let written = try desk.change(hash) { review throws(ReviewRefusal) in
            try review.write(text: text, at: time, region: region, to: thread, on: onScreen, now: Date())
        }
        let keyframe = layout.keyframe(written.thread.id, of: hash)
        if !written.thread.isGeneral, !FileManager.default.fileExists(atPath: keyframe.path) {
            if let pendingKeyframe {
                try? FileManager.default.moveItem(at: pendingKeyframe, to: keyframe)
            } else if let frame = written.thread.time {
                try? await FrameGrabber.writeImages(
                    of: asset, at: frame, duration: showing.duration, frameDuration: showing.frameDuration,
                    keyframe: keyframe, region: nil, crop: nil
                )
            }
        }
        if let pendingCrop {
            do {
                let crop = layout.crop(written.message.id, of: hash)
                try FileManager.default.createDirectory(at: crop.deletingLastPathComponent(), withIntermediateDirectories: true)
                try FileManager.default.moveItem(at: pendingCrop, to: crop)
            } catch {
                _ = try? desk.change(hash) { review throws(ReviewRefusal) in try review.delete(written.message.id) }
                throw AppRefusal("couldn't keep the crop of the region: \(error.localizedDescription)")
            }
        }
        if self.video == video {
            selection = written.thread.id
            tourNoticedQueued()
        }
        return written
    }

    private func report(_ message: Message) -> StateReport.Message {
        StateReport.Message(message, review: reviewKey ?? .video(contentHash: ""), layout: layout)
    }

    func keyframe(of thread: ReviewThread) -> URL? {
        reviewKey.flatMap { layout.keyframe(of: thread, on: $0) }
    }

    func crop(of message: Message) -> URL? {
        reviewKey.flatMap { layout.crop(of: message, on: $0) }
    }

    var frameMarks: [FrameMark] {
        guard video != nil else { return [] }
        return marks(of: frameThreads, at: engine.frameTime(of: engine.time))
    }

    func frameMarks(on side: CompareSide?) -> [FrameMark] {
        guard let side, let pair, let companion, side != activeSide else { return frameMarks }
        let other = pair.engine(side)
        let anchor = VersionAnchor(path: companion.url.path)
        return marks(of: threads.filter { !$0.isGeneral && $0.anchor == anchor }, at: other.frameTime(of: other.time))
    }

    private func marks(of threads: [ReviewThread], at frame: Double) -> [FrameMark] {
        threads.compactMap { thread in
            guard let time = thread.time, abs(time - frame) < 0.0005 else { return nil }
            return FrameMark(
                thread: thread.id, number: thread.number, state: thread.state ?? .queued,
                regions: thread.messages.compactMap(\.region)
            )
        }
    }

    var draftThreadNumber: Int? {
        guard let draft, let review = review else { return nil }
        return review.thread(atFrame: draft.time, on: onScreen)?.number ?? review.nextThreadNumber
    }

    private static let noVideo = AppRefusal("no video is open in the window; load one with `havooch player load <path>`")

    func needVideo() throws(AppRefusal) {
        guard video != nil else { throw Self.noVideo }
    }

    private func needInside(_ seconds: Double) throws(AppRefusal) {
        guard (0...engine.duration).contains(seconds) else {
            throw AppRefusal(
                "\(TimeCode.text(seconds)) is outside the video (0:00 to \(TimeCode.text(engine.duration)))"
            )
        }
    }

    private func needWords(_ text: String) throws(AppRefusal) {
        guard Self.hasWords(text) else { throw AppRefusal(ReviewRefusal.emptyText.line) }
    }

    static func hasWords(_ text: String) -> Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func messageID(_ text: String) throws(AppRefusal) -> MessageID {
        guard let id = ItemID(text), id.kind == .message else {
            throw AppRefusal(ReviewRefusal.unknownID(text).line)
        }
        return id
    }

    func togglePlay() {
        guard video != nil else { return }
        if isPlaying {
            pausePlayers()
        } else {
            closePopover(.momentChanged)
            playPlayers()
        }
    }

    func skip(by seconds: Double) {
        move(to: engine.time + seconds)
    }

    func step(frames: Int) {
        pausePlayers()
        move(to: engine.time + Double(frames) * engine.frameDuration)
    }

    private(set) var isSoundPanelOpen = false
    var speakerArea: CGRect = .zero
    @ObservationIgnored let soundClicks = SoundPanelClicks()

    func toggleSoundPanel() {
        isSoundPanelOpen.toggle()
    }

    func setSoundPanel(open: Bool) throws(AppRefusal) {
        if open, video == nil { throw Self.noVideo }
        isSoundPanelOpen = open
    }

    var soundReport: StateReport.Sound {
        StateReport.Sound(app.sound, panelOpen: isSoundPanelOpen && video != nil)
    }

    func setSpeed(_ speed: Double) {
        if let pair { pair.setSpeed(speed) } else { engine.speed = speed }
    }

    func scrub(to seconds: Double) {
        move(to: seconds)
    }

    private func move(to seconds: Double) {
        guard video != nil else { return }
        closePopover(.momentChanged)
        let target = min(max(seconds, 0), engine.duration)
        Task { await seekPlayers(to: target) }
    }

    func startDraft(region: Region? = nil) {
        guard video != nil else { return }
        if draft != nil {
            guard region != nil else { return }
            closePopover(.clickOutside)
        }
        pausePlayers()
        let time = engine.frameTime(of: engine.time)
        draft = Draft(time: time, text: "", region: region)
        if let region { drawnRegion = Draft(time: time, text: "", region: region) }
    }

    func closePopover(_ reason: PopoverClose) {
        guard let draft else { return }
        self.draft = nil
        if reason == .discard { dropDrawnRegion(draft) }
        guard reason != .discard, Self.hasWords(draft.text) else { return }
        deliver(draft)
    }

    private func dropDrawnRegion(_ draft: Draft) {
        guard let region = draft.region, drawnRegion?.region == region, drawnRegion?.time == draft.time else { return }
        drawnRegion = nil
    }

    private func takeKeysFromText() {
        guard let window = nsWindow, window.firstResponder is NSText else { return }
        window.makeFirstResponder(nil)
    }

    private func deliver(_ draft: Draft) {
        dropDrawnRegion(draft)
        guard let thread = review?.thread(atFrame: draft.time, on: onScreen), thread.openQuestion != nil else {
            queue(draft)
            return
        }
        if !answerQuestion(thread.id, text: draft.text), self.draft?.text.isEmpty != false {
            self.draft = draft
        }
    }

    func clickFrame() {
        takeKeysFromText()
        if draft != nil { closePopover(.clickOutside) }
    }

    func beginRegion() {
        guard video != nil else { return }
        takeKeysFromText()
        closePopover(.clickOutside)
        pausePlayers()
        isDrawingRegion = true
    }

    func endRegion(_ region: Region?) {
        guard isDrawingRegion else { return }
        isDrawingRegion = false
        if let region { startDraft(region: region) }
    }

    @discardableResult
    func escape() -> Bool {
        if isSoundPanelOpen {
            isSoundPanelOpen = false
            return true
        }
        if closeVersionPicker() { return true }
        if closeComparePicker() { return true }
        if compare?.phase == .choosing {
            compare = nil
            return true
        }
        if isDrawingRegion {
            isDrawingRegion = false
            return true
        }
        if draft != nil {
            closePopover(.discard)
            return true
        }
        if versionMenu != nil {
            versionMenu = nil
            return true
        }
        if isComparing {
            exitCompare()
            return true
        }
        guard shown != nil || connect != nil, isSidebarVisible else { return false }
        if connect != nil {
            closeConnect()
            return true
        }
        _ = showThreadList()
        return true
    }

    func commitDraft() {
        guard let draft, Self.hasWords(draft.text) else { return }
        self.draft = Draft(time: draft.time, text: "", region: nil)
        deliver(draft)
    }

    var draftThread: ReviewThread? {
        guard let draft else { return nil }
        return review?.thread(atFrame: draft.time, on: onScreen)
    }

    func openThread(_ id: ThreadID) {
        guard let thread = review?.thread(id), thread.anchor == onScreen else {
            Task {
                guard let thread = review?.thread(id), await showVersion(of: thread), let time = startThread(id) else { return }
                await seekPlayers(to: time)
            }
            return
        }
        guard let time = startThread(id) else { return }
        Task { await seekPlayers(to: time) }
    }

    func openThread(_ ref: String, frame: PopoverFrame?) async throws(AppRefusal) -> StateReport.Popover {
        try needVideo()
        let (id, key) = try desk.threadID(ref, open: reviewKey)
        guard key == reviewKey else { throw AppRefusal(ReviewRefusal.otherVideo(id.text).line) }
        guard let thread = review?.thread(id), !thread.isGeneral else {
            throw AppRefusal("General has no frame to open a popover on; its messages are in the sidebar")
        }
        guard await showVersion(of: thread) else {
            throw AppRefusal("#\(thread.number) is on a removed version, which has no frame to open a popover on")
        }
        if let frame { try movePopover(id, to: frame) }
        guard let time = startThread(id) else { throw Self.noVideo }
        await committing?.value
        await seekPlayers(to: time)
        guard let popover = state().popover else { throw Self.noVideo }
        return popover
    }

    private func startThread(_ id: ThreadID) -> Double? {
        guard let thread = review?.thread(id), let time = thread.time else { return nil }
        selection = id
        shown = id
        pausePlayers()
        if draft?.time != time {
            closePopover(.momentChanged)
            draft = Draft(time: time, text: "", region: nil)
        }
        return time
    }

    func openPopover(text: String, region: Region?) throws(AppRefusal) -> StateReport.Popover {
        try needVideo()
        closePopover(.clickOutside)
        startDraft(region: region)
        draft?.text = text
        guard let popover = state().popover else { throw Self.noVideo }
        return popover
    }

    private func queue(_ draft: Draft) {
        let before = committing
        let showing = self.showing
        commitsUnderWay += 1
        committing = Task {
            defer { commitsUnderWay -= 1 }
            await before?.value
            do throws(AppRefusal) {
                _ = try await queueMessage(text: draft.text, time: draft.time, region: draft.region, thread: nil, on: showing)
            } catch {
                if self.draft?.text.isEmpty != false { self.draft = draft }
                problem = Problem(title: "The message wasn't queued", reason: error.reason)
            }
        }
    }

    func send() {
        if let target = composerTarget, target.answers, let thread = target.thread, Self.hasWords(composerText) {
            let text = composerText
            if answerQuestion(thread, text: text) { spendComposer(target, text: text) }
        }
        guard canSend, !isSending else { return }
        isSending = true
        Task {
            defer { isSending = false }
            do throws(AppRefusal) {
                _ = try await sendQueue()
            } catch {
                problem = Problem(title: "The messages weren't sent", reason: error.reason)
            }
        }
    }

    private(set) var compare: CompareSession?
    private(set) var pair: PlayerPair?
    private(set) var companion: OpenVideo?

    var isComparing: Bool { pair != nil }
    var activeSide: CompareSide? { pair?.side(of: engine) }
    var isPlaying: Bool { pair?.isPlaying ?? engine.isPlaying }

    private func playPlayers() {
        if let pair { pair.play() } else { engine.play() }
    }

    private func pausePlayers() {
        if let pair { pair.pause() } else { engine.pause() }
    }

    private func seekPlayers(to seconds: Double) async {
        if let pair { await pair.seek(to: seconds) } else { await engine.seek(to: seconds) }
    }

    struct Showing {
        var video: OpenVideo
        var anchor: VersionAnchor?
        var asset: AVURLAsset?
        var duration: Double
        var frameDuration: Double
    }

    private var showing: Showing? {
        video.map {
            Showing(video: $0, anchor: onScreen, asset: engine.asset, duration: engine.duration, frameDuration: engine.frameDuration)
        }
    }

    var canCompare: Bool {
        project != nil && (projectOutline?.versions.count ?? 0) >= 2 && !isComparing
    }

    var compareOpening: CompareSession? { try? openingCompare() }

    func versionPath(_ number: Int) -> String? {
        projectOutline?.version(number)?.path
    }

    private func openingCompare() throws(AppRefusal) -> CompareSession {
        try needVideo()
        guard project != nil, let outline = projectOutline else {
            throw AppRefusal("this window holds a plain video, which has no versions to compare; `project new` makes it a project")
        }
        guard let session = CompareSession.opening(versions: outline.versions.count, onScreen: versionNumber) else {
            throw AppRefusal("the project has 1 version; Compare needs two, and `project add` adds the next")
        }
        return session
    }

    private func needPopoverPhase() throws(AppRefusal) {
        guard !isComparing else {
            throw AppRefusal("the window compares already; `compare set` changes it and `compare exit` ends it")
        }
    }

    func openCompare() throws(AppRefusal) {
        try needPopoverPhase()
        let session = try openingCompare()
        versionPicker = nil
        compare = session
    }

    func toggleCompare() {
        if compare?.phase == .choosing {
            compare = nil
        } else {
            try? openCompare()
        }
    }

    func pickCompareSide(_ side: CompareSide, query: String = "") throws(AppRefusal) {
        try needPopoverPhase()
        if compare == nil { try openCompare() }
        compare?.picker = CompareSession.SidePicker(side: side, picker: VersionPicker(query: query))
    }

    func toggleComparePicker(_ side: CompareSide) {
        if compare?.picker?.side == side {
            closeComparePicker()
        } else {
            try? pickCompareSide(side)
        }
    }

    @discardableResult
    func closeComparePicker() -> Bool {
        guard compare?.picker != nil else { return false }
        compare?.picker = nil
        return true
    }

    func typeCompareQuery(_ query: String) {
        guard compare?.picker != nil else { return }
        compare?.picker?.picker = VersionPicker(query: query)
    }

    func moveCompareHighlight(by steps: Int) {
        guard let open = compare?.picker, let versions = versionSwitch else { return }
        compare?.picker?.picker = open.picker.moved(by: steps, in: versions.matches(open.picker.query))
    }

    func pickHighlightedCompareVersion() {
        guard let open = compare?.picker, let versions = versionSwitch,
              let number = open.picker.highlight(in: versions.matches(open.picker.query))
        else { return }
        changeCompareForPerson(placing(number, on: open.side))
    }

    private func placing(_ number: Int, on side: CompareSide) -> CompareChange {
        side == .left ? CompareChange(left: number) : CompareChange(right: number)
    }

    func changeCompareForPerson(_ change: CompareChange) {
        Task {
            do throws(AppRefusal) {
                try await setCompare(change)
            } catch {
                problem = Problem(title: "The comparison didn't change", reason: error.reason)
            }
        }
    }

    func setCompare(_ change: CompareChange) async throws(AppRefusal) {
        try needVideo()
        guard var session = compare else {
            throw AppRefusal("Compare isn't open; `compare open` opens its popover and `compare start` compares")
        }
        let count = projectOutline?.versions.count ?? 0
        for number in [change.left, change.right].compactMap(\.self) where !(1...max(count, 1)).contains(number) {
            throw AppRefusal("the project has no v\(number); it has v1 to v\(count)")
        }
        guard session.phase == .comparing else {
            guard change.side == nil else {
                throw AppRefusal("the side messages go to is picked on the stage, once the window compares")
            }
            if let left = change.left { session.pick(left, for: .left) }
            if let right = change.right { session.pick(right, for: .right) }
            if let layout = change.layout { session.layout = layout }
            if let slider = change.slider { session.slide(to: slider) }
            compare = session
            return
        }
        if let left = change.left { try await show(left, on: .left) }
        if let right = change.right { try await show(right, on: .right) }
        if let layout = change.layout, compare?.layout != layout {
            compare?.layout = layout
            if layout == .flip, let side = activeSide { compare?.showing = side }
        }
        if let side = change.side { activate(side) }
        if let slider = change.slider { compare?.slide(to: slider) }
    }

    func swapCompare() throws(AppRefusal) {
        try needVideo()
        guard compare != nil else {
            throw AppRefusal("Compare isn't open; `compare open` opens its popover and `compare start` compares")
        }
        compare?.picker = nil
        compare?.swap()
        guard let pair else { return }
        pair.swap()
        if compare?.layout == .flip, let side = activeSide { compare?.showing = side }
    }

    @discardableResult
    func flipCompare() -> Bool {
        guard isComparing, compare?.layout == .flip, let side = activeSide else { return false }
        activate(side.other)
        return true
    }

    func slideCompare(to fraction: Double) {
        guard isComparing else { return }
        compare?.slide(to: fraction)
    }

    func startCompare() async throws(AppRefusal) {
        guard !isComparing else { return }
        var session: CompareSession
        if let compare { session = compare } else { session = try openingCompare() }
        session.picker = nil
        let wasPlaying = isPlaying
        closePopover(.momentChanged)
        await committing?.value
        versionPicker = nil
        if versionNumber.flatMap(session.side(of:)) == nil {
            try await switchVersion(to: session.number(.right))
        }
        guard let project, let video, let outline = projectOutline, let mine = versionNumber.flatMap(session.side(of:)),
              let version = outline.version(session.number(mine.other))
        else {
            throw AppRefusal("the comparison didn't open: the window changed meanwhile")
        }
        let (other, theirs) = try await loadSide(version.path)
        guard self.video == video, self.project == project, !isComparing else {
            other.retire()
            throw AppRefusal("the comparison didn't open: the window changed meanwhile")
        }
        engine.pause()
        let pair = mine == .left
            ? PlayerPair(left: engine, right: other, lead: .left)
            : PlayerPair(left: other, right: engine, lead: .right)
        companion = theirs
        self.pair = pair
        session.phase = .comparing
        compare = session
        record(theirs, playedBy: other)
        record(video, playedBy: engine)
        activate(session.layout == .flip ? session.showing : .right)
        if wasPlaying { pair.play() }
    }

    func startCompareForPerson() {
        Task {
            do throws(AppRefusal) {
                try await startCompare()
            } catch {
                problem = Problem(title: "The comparison didn't open", reason: error.reason)
            }
        }
    }

    @discardableResult
    func exitCompare() -> Bool {
        guard compare != nil else { return false }
        guard let pair else {
            compare = nil
            return true
        }
        activate(.right)
        closePopover(.momentChanged)
        isDrawingRegion = false
        let other = pair.engine(.left)
        pair.end()
        other.retire()
        self.pair = nil
        companion = nil
        compare = nil
        return true
    }

    func clickFrame(on side: CompareSide?) {
        if let side, isComparing, side != activeSide {
            takeKeysFromText()
            activate(side)
            return
        }
        clickFrame()
    }

    func beginRegion(on side: CompareSide?) {
        if let side, isComparing { activate(side) }
        beginRegion()
    }

    func activate(_ side: CompareSide) {
        guard let pair, let companion, let video, activeSide != side else { return }
        closePopover(.momentChanged)
        isDrawingRegion = false
        drawnRegion = nil
        self.companion = video
        self.video = companion
        engine = pair.engine(side)
        pair.lead = side
        sidecar = ContextReader.sidecar(beside: companion.url)
        if compare?.layout == .flip { compare?.showing = side }
        record(companion, playedBy: engine)
    }

    private func show(_ number: Int, on side: CompareSide) async throws(AppRefusal) {
        guard let session = compare, let pair, session.number(side) != number else { return }
        guard session.number(side.other) != number else {
            try swapCompare()
            return
        }
        guard let version = projectOutline?.version(number) else { throw Self.noVideo }
        let (loaded, shown) = try await loadSide(version.path)
        guard self.pair === pair, compare?.number(side) == session.number(side) else {
            loaded.retire()
            throw AppRefusal("the comparison changed before v\(number) opened")
        }
        let wasPlaying = isPlaying
        pausePlayers()
        if side == activeSide {
            closePopover(.momentChanged)
            await committing?.value
            guard self.pair === pair else {
                loaded.retire()
                throw AppRefusal("the comparison ended before v\(number) opened")
            }
        }
        await loaded.seek(to: min(engine.time, loaded.duration))
        let old = pair.replace(side, with: loaded)
        if old === engine {
            engine = loaded
            self.video = shown
            forgetVideoViews(keepingReview: true)
            sidecar = ContextReader.sidecar(beside: shown.url)
        } else {
            companion = shown
        }
        old.retire()
        compare?.pick(number, for: side)
        record(shown, playedBy: loaded)
        if let video = self.video { record(video, playedBy: engine) }
        if wasPlaying { pair.play() }
    }

    private func loadSide(_ path: String) async throws(AppRefusal) -> (PlayerEngine, OpenVideo) {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        try AppModel.needFile(url)
        guard let contentHash = await Self.contentHash(of: url, in: app.hashes) else {
            throw AppRefusal("can't read \(url.path)")
        }
        let loaded = PlayerEngine(sound: app.sound)
        do {
            try await loaded.load(url)
        } catch {
            loaded.retire()
            throw error
        }
        loaded.speed = engine.speed
        await loaded.seek(to: min(engine.time, loaded.duration))
        return (loaded, OpenVideo(url: url, title: url.lastPathComponent, contentHash: contentHash))
    }

    private func record(_ video: OpenVideo, playedBy engine: PlayerEngine) {
        let frameRate = 1 / engine.frameDuration
        let info = VideoInfo(
            contentHash: video.contentHash, title: video.title, duration: engine.duration, path: video.url.path, frameRate: frameRate
        )
        _ = try? change { review in review.show(info) }
        transcripts.opened(VideoFile(url: video.url, contentHash: video.contentHash, frameRate: frameRate, duration: engine.duration))
    }

    var compareReport: StateReport.Compare? {
        guard let compare else { return nil }
        let picker = compare.picker.map { open in
            let matches = versionSwitch?.matches(open.picker.query) ?? []
            return StateReport.Compare.Picker(
                side: open.side.rawValue, query: open.picker.query, matches: matches.map(\.number),
                highlighted: open.picker.highlight(in: matches)
            )
        }
        return StateReport.Compare(
            phase: compare.phase.rawValue, left: compare.number(.left), right: compare.number(.right),
            layout: compare.layout.rawValue, showing: compare.layout == .flip ? compare.showing.rawValue : nil,
            slider: compare.slider, active: activeSide?.rawValue, picker: picker
        )
    }

    func showThread(_ id: ThreadID) {
        guard let thread = show(id) else { return }
        guard let time = thread.time else { return }
        guard thread.anchor == onScreen else {
            Task {
                guard await showVersion(of: thread), show(id) != nil else { return }
                move(to: time)
            }
            return
        }
        move(to: time)
    }

    func showThread(_ ref: String) async throws(AppRefusal) -> (sidebar: StateReport.Sidebar, number: Int) {
        try needVideo()
        let (id, key) = try desk.threadID(ref, open: reviewKey)
        guard key == reviewKey, let found = review?.thread(id) else {
            throw AppRefusal(ReviewRefusal.otherVideo(id.text).line)
        }
        let onItsVersion = await showVersion(of: found)
        guard let thread = show(id) else { throw AppRefusal(ReviewRefusal.otherVideo(id.text).line) }
        if onItsVersion, let time = thread.time {
            closePopover(.momentChanged)
            await committing?.value
            await seekPlayers(to: time)
        }
        return (sidebarReport, id.number)
    }

    private func show(_ id: ThreadID) -> ReviewThread? {
        guard let thread = review?.thread(id) else { return nil }
        selection = id
        shown = id
        pausePlayers()
        return thread
    }

    private func markSeen(_ id: ThreadID) {
        guard review?.thread(id) != nil else { return }
        _ = try? change { review throws(ReviewRefusal) in try review.markSeen(id, at: Date()) }
    }

    var isControlFocused: Bool { !focusedControls.isEmpty }

    func focusControl(_ id: UUID, press: @escaping () -> Void) {
        focusedControls.removeAll { $0.id == id }
        focusedControls.append((id, press))
    }

    func blurControl(_ id: UUID) {
        focusedControls.removeAll { $0.id == id }
    }

    @discardableResult
    func pressFocusedControl() -> Bool {
        guard let control = focusedControls.last else { return false }
        control.press()
        return true
    }

    func perform(_ action: RowAction, on id: ThreadID) {
        switch action {
        case .open: showThread(id)
        case .showOnVideo: showOnVideo(id)
        case .deleteQueued: deleteQueued(on: id)
        }
    }

    func rowActions(for thread: ReviewThread) -> [RowAction] {
        var actions: [RowAction] = [.open]
        if !thread.isGeneral { actions.append(.showOnVideo) }
        if thread.messages.contains(where: { $0.state == .queued }) { actions.append(.deleteQueued) }
        return actions
    }

    func showOnVideo(_ id: ThreadID) {
        guard let thread = review?.thread(id), let time = thread.time else { return }
        guard thread.anchor == onScreen else {
            Task {
                guard await showVersion(of: thread) else { return }
                selection = id
                pausePlayers()
                move(to: time)
            }
            return
        }
        selection = id
        pausePlayers()
        move(to: time)
    }

    func deleteQueued(on id: ThreadID) {
        let queued = review?.thread(id)?.messages.filter { $0.state == .queued }.map(\.id) ?? []
        for message in queued { delete(message) }
    }

    func showThreadList() -> StateReport.Sidebar {
        shown = nil
        connect = nil
        return sidebarReport
    }

    func showNeighbour(forward: Bool) {
        guard let next = neighbour(forward: forward) else { return }
        showThread(next.id)
    }

    func neighbour(forward: Bool) -> ReviewThread? {
        let threads = threads
        guard let shown, let index = threads.firstIndex(where: { $0.id == shown }) else { return nil }
        let next = index + (forward ? 1 : -1)
        return threads.indices.contains(next) ? threads[next] : nil
    }

    private(set) var pickedVersions: [Int] = []
    private(set) var versionMenu: String?
    private(set) var versionJump: VersionJump?

    struct VersionJump: Equatable {
        var number: Int
        var serial: Int
    }

    var versionTree: VersionTree? {
        guard let outline = projectOutline else { return nil }
        return VersionTree(outline: outline, threads: threads, onScreen: versionNumber, picked: pickedVersions)
    }

    var allVersionsMenu: AllVersionsMenu? {
        guard let versionMenu, let tree = versionTree else { return nil }
        return AllVersionsMenu(tree: tree, query: versionMenu)
    }

    private func needVersionTree() throws(AppRefusal) -> VersionTree {
        try needVideo()
        guard let tree = versionTree else {
            throw AppRefusal("the thread list shows versions only in a project; this window holds a plain video")
        }
        return tree
    }

    func openVersionMenu(search: String?) throws(AppRefusal) -> StateReport.Sidebar {
        _ = try needVersionTree()
        shown = nil
        connect = nil
        versionMenu = search ?? versionMenu ?? ""
        return sidebarReport
    }

    func typeVersionSearch(_ text: String) {
        guard versionMenu != nil else { return }
        versionMenu = text
    }

    func closeVersionMenu() -> StateReport.Sidebar {
        versionMenu = nil
        return sidebarReport
    }

    func pickVersion(_ number: Int) throws(AppRefusal) -> StateReport.Sidebar {
        let tree = try needVersionTree()
        guard tree.versions.contains(where: { $0.number == number }) else {
            throw AppRefusal("the project has no v\(number); it has v1 to v\(tree.versions.count)")
        }
        shown = nil
        connect = nil
        versionMenu = nil
        if !tree.shown.contains(number) {
            pickedVersions.removeAll { $0 == number }
            pickedVersions.insert(number, at: 0)
        }
        versionJump = VersionJump(number: number, serial: (versionJump?.serial ?? 0) + 1)
        return sidebarReport
    }

    func removePickedVersion(_ number: Int) throws(AppRefusal) -> StateReport.Sidebar {
        let tree = try needVersionTree()
        guard let section = tree.sections.first(where: { $0.number == number }), section.isPicked else {
            throw AppRefusal("v\(number) isn't picked from All versions; the last three versions and the one on screen stay")
        }
        pickedVersions.removeAll { $0 == number }
        return sidebarReport
    }

    var threadGroups: [ThreadGroup.Section] { ThreadGroup.sections(of: threads) }

    var othersNeedingYou: Int {
        threads.filter { $0.openQuestion != nil && $0.id != shown }.count
    }

    var stageThread: ThreadID? {
        frameMarks.first?.thread
    }

    var sidebarReport: StateReport.Sidebar {
        var report = StateReport.Sidebar(thread: shown?.text, width: Double(sidebarWidth), composer: composerReport)
        report.mode = connect != nil ? "connect" : shown != nil ? "thread" : "threads"
        report.connect = connectReport
        report.versions = versionTree.map { StateReport.Sidebar.Versions($0, menu: allVersionsMenu, search: versionMenu) }
        return report
    }

    var composerTarget: ComposerTarget? {
        guard video != nil, let review = review else { return nil }
        let frame = engine.frameTime(of: engine.time)
        let shownThread = shown.flatMap { review.thread($0) }
        return ComposerTarget.resolve(
            shown: shownThread,
            general: shownThread == nil && isComposerGeneral ? threads.first(where: \.isGeneral) : nil,
            atFrame: review.thread(atFrame: frame, on: onScreen),
            frame: frame,
            nextNumber: review.nextThreadNumber,
            regionTime: drawnRegion.map(\.time).flatMap { $0 == frame ? $0 : nil }
        )
    }

    var isPointingAtRegion: Bool { isDrawingRegion || composerRegion != nil }

    var composerRegion: Region? {
        guard composerTarget?.takesRegion == true else { return nil }
        return drawnRegion?.region
    }

    var composerText: String {
        get { composerTarget.flatMap { composerDrafts[$0.draftKey] } ?? "" }
        set {
            guard let key = composerTarget?.draftKey else { return }
            composerDrafts[key] = newValue.isEmpty ? nil : newValue
        }
    }

    func toggleComposerGeneral() {
        isComposerGeneral.toggle()
    }

    func removeComposerRegion() {
        drawnRegion = nil
    }

    func composerBegan() {
        pausePlayers()
    }

    func submitComposer() {
        guard Self.hasWords(composerText), !isComposing else { return }
        isComposing = true
        Task {
            defer { isComposing = false }
            do throws(AppRefusal) {
                _ = try await writeComposer()
            } catch {
                problem = Problem(title: "The message wasn't written", reason: error.reason)
            }
        }
    }

    @discardableResult
    func writeComposer() async throws(AppRefusal) -> ComposerTarget.Kind {
        guard let target = composerTarget else { throw Self.noVideo }
        let text = composerText
        try needWords(text)
        if target.answers, let thread = target.thread {
            _ = try answer(thread.text, text: text)
        } else {
            let region = target.takesRegion ? drawnRegion?.region : nil
            pausePlayers()
            _ = try await queueMessage(text: text, time: target.isGeneral ? nil : target.time, region: region, thread: target.thread)
            if region != nil, drawnRegion?.region == region { drawnRegion = nil }
        }
        spendComposer(target, text: text)
        return target.kind
    }

    private func spendComposer(_ target: ComposerTarget, text: String) {
        if composerDrafts[target.draftKey] == text { composerDrafts[target.draftKey] = nil }
        if target.isGeneral { isComposerGeneral = false }
    }

    func compose(text: String, region: Region?, general: Bool) throws(AppRefusal) -> StateReport.Sidebar.Composer {
        try needVideo()
        pausePlayers()
        isComposerGeneral = general
        if let region {
            drawnRegion = Draft(time: engine.frameTime(of: engine.time), text: "", region: region)
        }
        composerText = text
        composerFocusRequests += 1
        guard let report = composerReport else { throw Self.noVideo }
        return report
    }

    var composerReport: StateReport.Sidebar.Composer? {
        guard let target = composerTarget else { return nil }
        return StateReport.Sidebar.Composer(
            target: target.line, kind: target.kind.name, thread: target.thread?.text, number: target.number, time: target.time,
            general: isComposerGeneral && shown == nil, text: composerText, region: composerRegion
        )
    }

    var sidebarWidth: CGFloat { app.sidebarWidth }

    static func sidebarWidth(kept: Double?) -> CGFloat {
        guard let kept, kept.isFinite else { return Metrics.sidebarWidth }
        let range = Metrics.sidebarWidthRange
        return min(max(CGFloat(kept), range.lowerBound), range.upperBound)
    }

    func keepSidebarWidth(_ width: CGFloat) {
        app.keepSidebarWidth(width)
    }

    func jumpToMarker(forward: Bool) {
        let slack = engine.frameDuration / 2
        let pinned = frameThreads
        let next = forward
            ? pinned.first { ($0.time ?? 0) > engine.time + slack }
            : pinned.last { ($0.time ?? 0) < engine.time - slack }
        if let next { showThread(next.id) }
    }

    var agentName: String { listener?.outbox.session?.name ?? "Agent" }

    var agent: KnownAgent? { listener?.outbox.session?.agent }

    func raise(_ notice: Notice) {
        if notice.thread == shown { markSeen(notice.thread) }
        notices.append(notice)
        let expires = notice.expires
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(expires.timeIntervalSinceNow, 0)))
            self?.dismiss(notice.id)
        }
    }

    func dismiss(_ id: UUID) {
        notices.removeAll { $0.id == id }
    }

    func openNotice(_ id: UUID) {
        guard let notice = notices.first(where: { $0.id == id }) else { return }
        dismiss(id)
        if notice.thread.number == 0 {
            isSidebarVisible = true
            shown = notice.thread
        } else {
            openThread(notice.thread)
        }
    }

    @discardableResult
    func answerQuestion(_ thread: ThreadID, text: String) -> Bool {
        do throws(AppRefusal) {
            _ = try answer(thread.text, text: text)
            return true
        } catch {
            problem = Problem(title: "The answer wasn't sent", reason: error.reason)
            return false
        }
    }

    @discardableResult
    func chooseAnswer(_ thread: ThreadID, choice number: Int) -> Bool {
        do throws(AppRefusal) {
            _ = try choose(thread.text, choice: number)
            return true
        } catch {
            problem = Problem(title: "The answer wasn't sent", reason: error.reason)
            return false
        }
    }

    func edit(_ id: MessageID, text: String) {
        do throws(AppRefusal) {
            _ = try editMessage(id.text, text: text)
        } catch {
            problem = Problem(title: "The message didn't change", reason: error.reason)
        }
    }

    func delete(_ id: MessageID) {
        do throws(AppRefusal) {
            _ = try deleteMessage(id.text)
        } catch {
            problem = Problem(title: "The message wasn't deleted", reason: error.reason)
        }
    }

    var contextNote: String { review?.note ?? "" }

    var contextText: String? {
        ContextReader.text(sidecar: sidecar?.text, note: contextNote)
    }

    var isContextDue: Bool {
        guard let key = reviewKey else { return false }
        return listener?.outbox.isContextDue(for: key.contextKey, text: contextText) ?? false
    }

    func readSidecar() {
        sidecar = video.flatMap { ContextReader.sidecar(beside: $0.url) }
    }

    func saveContextNote(_ text: String) {
        do throws(AppRefusal) {
            try setContextNote(text)
            isContextShown = false
        } catch {
            problem = Problem(title: "The note wasn't saved", reason: error.reason)
        }
    }

    func openFromPanel() {
        app.openFromPanel(from: self)
    }

    func openForPerson(_ url: URL) {
        app.openForPerson(url, from: self)
    }
}
