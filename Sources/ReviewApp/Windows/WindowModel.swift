import AppKit
import Observation
import ReviewCore
import ReviewLease
import ReviewSetup
import ReviewStore
import ReviewTranscript
import ReviewWire
import UniformTypeIdentifiers

/// One window (ADR 0003): which video it holds, the message being written,
/// the selected thread, and every action a person or an operator can take
/// in it. Each window has its own player, popover, sidebar, queue and
/// notices; the data, the theme and the recent videos are the app's
/// (`AppModel`). The UI and the control server call the same methods, so a
/// click and its CLI command are one code path.
@Observable
final class WindowModel: WindowControlling {
    /// The video that's open.
    struct OpenVideo: Equatable {
        var url: URL
        /// The file's name without its extension.
        var title: String
        /// The hash of the file's content: the video's identity.
        var contentHash: String
    }

    /// Why the last thing the person asked for didn't work.
    struct Problem: Equatable {
        var title: String
        var reason: String
    }

    /// The app the window is one of: the data, the theme, the other windows.
    let app: AppModel
    /// The window's name in `window list` and for `--window`: `w1`, `w2`…,
    /// never used twice in a run.
    let id: String
    let engine = PlayerEngine()
    /// The AppKit window that shows this one; nil before its scene shows,
    /// and in tests.
    @ObservationIgnored weak var nsWindow: NSWindow?
    /// The data the run is on: every window's.
    var data: DataFolder { app.data }
    /// The reviews, and the one path for changing them.
    var desk: ReviewDesk { data.desk }
    /// The review the window's video is on; nil with no video. Its
    /// listener is the window's.
    var reviewKey: ReviewKey? { video.map { .video(contentHash: $0.contentHash) } }
    /// The window's listener (ADR 0003): its review's sends in line and
    /// whether an agent is there for them; nil with no video.
    var listener: ListenerQueue? { reviewKey.map(data.listeners.queue(for:)) }
    /// The transcripts of the videos opened on this data in this run.
    var transcripts: TranscriptDesk { data.transcripts }
    /// The active theme, the app's.
    var themes: ThemeDesk { app.themes }
    /// `config.toml`, the app's: its notice shows in every window.
    var config: ConfigDesk { app.config }
    /// Where the run keeps its data now: the person's own, or a demo's.
    var support: URL { data.support }
    /// Whether an in-app demo runs.
    var isInAppDemo: Bool { app.isInAppDemo }
    /// Whether the run is on demo data. The header's demo words follow it.
    var isDemo: Bool { app.isDemo }
    private(set) var video: OpenVideo?
    /// The open video's review; nil with no video.
    var review: VideoReview? { video.flatMap { desk.opened($0.contentHash) } }
    /// What the window holds, as its scene's value; nil for nothing.
    var target: WindowTarget? { video.map { .video(contentHash: $0.contentHash, path: $0.url.path) } }
    /// The message being written; nil while the popover is closed.
    var draft: Draft?
    /// The thread whose pin is picked out.
    private(set) var selection: ThreadID?
    /// The thread the sidebar shows in its thread view; nil while it
    /// shows the thread list (L38). Showing a thread's view marks its
    /// agent messages read (L46).
    private(set) var shown: ThreadID? {
        didSet {
            guard let shown else { return }
            markSeen(shown)
            // A thread's view takes the sidebar's place from the Connect view.
            connect = nil
        }
    }
    /// The Connect view in the sidebar, over the threads, and what opened
    /// it; nil while the sidebar shows the threads (G1).
    var connect: ConnectEntry?
    /// The harness the person picked in the Connect view; nil follows the
    /// setup (`connectHarness`).
    var pickedHarness: Harness?
    /// The controls that have the keyboard focus under keyboard navigation
    /// (`focusControl(_:press:)`), the last to take it at the end: Space
    /// and Return press that one. A control in a popover takes the focus
    /// while one in the player's window keeps its own; when the popover's
    /// control loses it, the window's control is pressed again. Empty
    /// while no control has the focus, and Space is the player's.
    @ObservationIgnored private var focusedControls: [(id: UUID, press: () -> Void)] = []
    /// Whether the person is dragging a rectangle on the frame.
    private(set) var isDrawingRegion = false
    /// Whether the sidebar is shown beside the stage.
    var isSidebarVisible = true
    /// Whether the context popover is open.
    var isContextShown = false
    /// The open video's sidecar context file, as it was last read.
    private(set) var sidecar: ContextReader.Sidecar?
    /// Shown to the person until they dismiss it.
    var problem: Problem?
    /// What the agent just said, shown on the stage: the newest last.
    private(set) var notices: [Notice] = []

    /// The composer's drafts (L41): one per target thread, and one for a
    /// new thread, in memory only.
    private(set) var composerDrafts: [ComposerTarget.DraftKey: String] = [:]
    /// Whether the composer in the thread list writes to General.
    private(set) var isComposerGeneral = false
    /// The last region drawn on the frame, on its frame: the composer's
    /// chip while the stage shows that frame. The popover's words take it
    /// first when they are written there.
    private(set) var drawnRegion: Draft?
    /// Grows each time something asks the composer's field for the keys:
    /// the field takes the focus when it changes.
    private(set) var composerFocusRequests = 0
    /// Whether the composer's words are on their way.
    private(set) var isComposing = false

    /// The stage in the window, from its top-left corner, as it was last
    /// laid out. A click on the stage closes the popover by the stage's own
    /// gestures; a click anywhere else in the window is outside it.
    @ObservationIgnored var stageArea: CGRect = .zero
    /// The player bar's track in the window, from its top-left corner: the
    /// popover on a moment points at the playhead on it.
    var trackArea: CGRect = .zero

    private var layout: SupportLayout { data.layout }
    /// The message the popover is queueing: its pictures are being
    /// written. A send waits for it.
    @ObservationIgnored private var committing: Task<Void, Never>?
    /// How many messages from the popover are on their way into the queue.
    private var commitsUnderWay = 0
    /// Whether a send the person asked for is on its way.
    @ObservationIgnored private var isSending = false

    /// A window of `app`, holding nothing, named `id`. `AppModel` makes
    /// windows (`makeWindow`).
    init(app: AppModel, id: String) {
        self.app = app
        self.id = id
    }

    /// The open video's transcript as `state` and the Context popover show
    /// it: its source, and how far it is.
    var transcript: StateReport.Transcript? {
        video.flatMap { transcripts.report(of: $0.contentHash) }
    }

    /// The open video's threads: General first, then in time order.
    var threads: [ReviewThread] { review?.threads ?? [] }

    /// The open video's threads on a frame: every one but General.
    var frameThreads: [ReviewThread] { threads.filter { !$0.isGeneral } }

    /// The open video's sends, in the order they were sent.
    var sends: [Send] { review?.sends ?? [] }

    /// Whether Cmd+Return has something to send: a queued message, one on
    /// its way into the queue, or words in the popover.
    var canSend: Bool {
        sendCount > 0
    }

    /// How many messages wait in the queue, as the sidebar's footer counts them.
    var queuedCount: Int { review?.queue.count ?? 0 }

    /// How many messages a send would deliver now: the queue, with the
    /// words in the popover and in the composer that would join it.
    var sendCount: Int {
        let popover = draft.map { Self.hasWords($0.text) } == true ? 1 : 0
        let composer = composerTarget.map { !$0.answers && Self.hasWords(composerText) } == true ? 1 : 0
        return (review?.queue.count ?? 0) + commitsUnderWay + popover + composer
    }

    // MARK: - Actions, for the person and the operator alike

    /// Opens `url` in this window, on the data the run is on when it's
    /// asked. Refused when the run switches to other data (the demo, or
    /// back) before it's open, so a video never lands on data it wasn't
    /// opened for, and when another window holds the video: no two windows
    /// hold one video (ADR 0003).
    func open(_ url: URL) async throws(AppRefusal) {
        let data = app.data
        let url = url.standardizedFileURL
        try AppModel.needFile(url)
        guard let contentHash = await Self.contentHash(of: url, in: app.hashes) else {
            throw AppRefusal("can't read \(url.path)")
        }
        try needOwn(contentHash, url)
        // Before the player changes: a history that doesn't read keeps the
        // video shut, and the one that was open stays open.
        // The file's name with its extension, the same in the header, the state and the payload.
        let title = url.lastPathComponent
        // Another video is a change of the moment: words in the popover are
        // queued on the video they were written on, before it goes.
        closePopover(.momentChanged)
        await committing?.value
        try needData(data, for: url)
        let found = try data.desk.review(for: VideoInfo(contentHash: contentHash, title: title, duration: 0, path: url.path))
        // Where the person left the video that goes, before the player takes the new one.
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
            // The switch, or going home, closed the video; the player stays empty.
            if video == nil { engine.close() }
            try needData(data, for: url)
            throw AppRefusal("\(url.path) didn't open: the video was closed meanwhile")
        }
        // Another window may have opened the same video meanwhile.
        do throws(AppRefusal) {
            try needOwn(contentHash, url)
        } catch {
            if video == nil { engine.close() }
            throw error
        }
        // The review as it is now, not as it was before the load: a
        // listener may have answered on one of its threads meanwhile.
        var review = data.desk.review(of: contentHash) ?? found
        video = OpenVideo(url: url, title: title, contentHash: contentHash)
        forgetVideoViews()
        sidecar = ContextReader.sidecar(beside: url)
        let frameRate = 1 / engine.frameDuration
        // The same content, where and as it is now: a renamed or moved copy
        // has its history, and the review records the new path.
        review.video = VideoInfo(
            contentHash: contentHash, title: title, duration: engine.duration, path: url.path, frameRate: frameRate
        )
        desk.open(review)
        desk.library.recordOpened(url, contentHash: contentHash, at: Date())
        app.refreshRecents()
        transcripts.opened(VideoFile(url: url, contentHash: contentHash, frameRate: frameRate, duration: engine.duration))
    }

    /// Refused when a window other than this one holds the video with
    /// `contentHash`, at `url`.
    private func needOwn(_ contentHash: String, _ url: URL) throws(AppRefusal) {
        guard let holder = app.windows.holding(contentHash), holder !== self else { return }
        throw AppRefusal("\(url.lastPathComponent) is open in window \(holder.id); one video opens in one window")
    }

    /// The window closed: words in the popover are queued on their video,
    /// as a change of the moment queues them, and the video pauses and
    /// keeps its position for its recent-video entry. Its review stays.
    func closed() {
        closePopover(.momentChanged)
        engine.pause()
        savePosition()
    }

    /// The hash of the file at `url`, read off the main actor: it reads the
    /// whole file, and a long video would hold the window still.
    @concurrent
    nonisolated static func contentHash(of url: URL, in hashes: ContentHashCache) async -> String? {
        hashes.of(url)
    }

    /// Refused when the run is no longer on `data`, the data `url` was
    /// being opened on.
    private func needData(_ data: DataFolder, for url: URL) throws(AppRefusal) {
        guard app.data.support == data.support else {
            throw AppRefusal("\(url.path) didn't open: the app switched to the data in \(self.data.support.path) meanwhile")
        }
    }

    /// What the window showed on the video that was open goes: the
    /// popover, the picked and shown threads, the drawn region, the
    /// composer's words and the notices.
    private func forgetVideoViews() {
        draft = nil
        selection = nil
        shown = nil
        connect = nil
        isDrawingRegion = false
        composerDrafts = [:]
        isComposerGeneral = false
        drawnRegion = nil
        notices = []
        isContextShown = false
    }

    /// "Try the Demo": the bundled launch video on demo data, in this
    /// window (`openDemo`). The person is shown why when it doesn't open.
    func tryDemo() {
        Task {
            do throws(AppRefusal) {
                try await openDemo()
            } catch {
                problem = Problem(title: "The demo didn't open", reason: error.reason)
            }
        }
    }

    /// "Try the Demo" and `app demo`: the bundled launch video on demo
    /// data, in this window (`AppModel.enterDemo`). Refused in a build with
    /// no bundled video.
    func openDemo() async throws(AppRefusal) {
        try await app.openDemo(in: self)
    }

    /// Goes home: the open video's position is saved and the video closes,
    /// and an in-app demo is left, so the window shows the home screen on
    /// the person's data. As opening another video does, words in the
    /// popover are first queued on their video, the composer's words go,
    /// and the queue stays on the video's review. A run started with
    /// `app open --demo` stays on its folder. Leaving an in-app demo takes
    /// every window home, since every window is on the run's data.
    func goHome() async {
        if isInAppDemo {
            await app.leaveDemo()
        } else {
            await settle()
            leaveData()
        }
        // A file moved since home last showed turns its card unavailable.
        app.refreshRecents()
    }

    /// A click on the Havooch mark in the header, and File > Close Video:
    /// `goHome`.
    func goHomeForPerson() {
        Task { await goHome() }
    }

    /// Words in the popover are queued on the video they were written on,
    /// and every message on its way into the queue is there: before the
    /// video goes, or the run switches its data.
    func settle() async {
        closePopover(.momentChanged)
        await committing?.value
    }

    /// The video goes, its position kept in the recent videos of its own
    /// data: going home, and before the run switches its data.
    func leaveData() {
        savePosition()
        closeVideo()
    }

    /// No video is open any more: the player is empty, and what was on
    /// the video goes with it. Its review stays kept, so a listener can
    /// still answer on it.
    private func closeVideo() {
        closes += 1
        engine.close()
        video = nil
        forgetVideoViews()
        sidecar = nil
    }

    // MARK: - Recent videos

    /// The recent videos of the run's data, the newest first: the home
    /// screen's cards. The app's, the same in every window.
    var recents: [StateReport.Recent] { app.recents }

    /// How many `open`s are loading their video into the player.
    @ObservationIgnored private var loads = 0
    /// Grows each time the open video closes: an `open` whose load a close
    /// overtook leaves the player empty.
    @ObservationIgnored private var closes = 0

    /// Keeps where the playhead is as the open video's last position, for
    /// its recent-video entry. Opening another video, closing the window,
    /// quitting and going home call it. Nothing with no video.
    func savePosition() {
        // While a load runs, the player already holds the next video's
        // time; `open` saved this one's before the load.
        guard let video, loads == 0 else { return }
        desk.library.savePosition(engine.time, of: video.contentHash)
        app.refreshRecents()
    }

    /// Takes the video with `contentHash` off the recent videos. Its review
    /// stays on disk.
    func removeRecent(_ contentHash: String) {
        app.removeRecent(contentHash)
    }

    /// Has the home screen read the recent videos again.
    func refreshRecents() {
        app.refreshRecents()
    }

    /// A click on a recent video's card: opens its video, in this window
    /// unless another one holds it. A card whose file is not there does
    /// nothing; its trash button removes it.
    func openRecent(_ recent: StateReport.Recent) {
        guard recent.available else { return }
        openForPerson(recent.url)
    }

    /// The recent videos' thumbnails, the app's.
    var thumbnails: Thumbnails { app.thumbnails }

    func play() throws(AppRefusal) {
        try needVideo()
        closePopover(.momentChanged)
        engine.play()
    }

    func pause() throws(AppRefusal) {
        try needVideo()
        engine.pause()
    }

    func seek(to seconds: Double) async throws(AppRefusal) {
        try needVideo()
        try needInside(seconds)
        closePopover(.momentChanged)
        // `seek` answers once the popover's words are in the queue, so
        // `state` after it shows them.
        await committing?.value
        await engine.seek(to: seconds)
    }

    /// `comment add`: queues a message, as a person would. On `thread` (a
    /// thread id or a number of the open video) it's written on that
    /// thread, and the player moves to the thread's frame. Otherwise it
    /// joins the thread of the frame at `at`, or where the player is, or
    /// starts one. `at` beside a thread must be the thread's frame. Every
    /// refusal comes before the player moves or an image is written.
    func addMessage(
        text: String, at: Double?, region: Region? = nil, thread ref: String? = nil
    ) async throws(AppRefusal) -> (message: StateReport.Message, thread: StateReport.Thread) {
        try needVideo()
        try needWords(text)
        if let at { try needInside(at) }
        guard let review = review else { throw Self.noVideo }
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
        // A message the review refuses leaves the player where it is.
        var trial = review
        do throws(ReviewRefusal) {
            _ = try trial.write(text: text, at: time, region: region, to: thread?.id, now: Date())
        } catch {
            throw AppRefusal(error.line)
        }
        engine.pause()
        if let time {
            // The words in the popover are queued at their own frame first.
            closePopover(.momentChanged)
            await committing?.value
            await engine.seek(to: time)
        }
        let written = try await queueMessage(text: text, time: time, region: region, thread: thread?.id)
        guard let video else { throw Self.noVideo }
        return (
            StateReport.Message(written.message, contentHash: video.contentHash, layout: layout),
            StateReport.Thread(written.thread, contentHash: video.contentHash, layout: layout)
        )
    }

    /// `comment edit` and a row's Save: a queued message's new text.
    func editMessage(_ id: String, text: String) throws(AppRefusal) -> StateReport.Message {
        let id = try messageID(id)
        let message = try change { review throws(ReviewRefusal) in try review.edit(id, text: text) }
        return report(message)
    }

    /// `comment delete` and a row's Delete: a queued message goes, with its
    /// crop; a thread that loses its last message goes, with its keyframe.
    func deleteMessage(_ id: String) throws(AppRefusal) -> StateReport.Message {
        let id = try messageID(id)
        let deleted = try change { review throws(ReviewRefusal) in try review.delete(id) }
        let report = report(deleted.message)
        if let crop = report.cropPath { ImageFiles.remove(URL(fileURLWithPath: crop)) }
        if deleted.removedThread, let video {
            ImageFiles.remove(layout.keyframe(deleted.thread, of: video.contentHash))
            if selection == deleted.thread { selection = nil }
            // A thread view of a thread that's gone goes back to the list.
            if shown == deleted.thread { shown = nil }
        }
        return report
    }

    /// The end of a drag or a resize of a thread's popover: where it
    /// opens from now on.
    func movePopover(_ thread: ThreadID, to frame: PopoverFrame?) throws(AppRefusal) {
        try change { review throws(ReviewRefusal) in try review.setPopoverFrame(thread, frame) }
    }

    /// The context popover's Save and `context set`: the open video's
    /// context note, kept without the space around it. The listener gets
    /// it under the sidecar's text with the next send. An empty text clears
    /// the note.
    @discardableResult
    func setContextNote(_ text: String) throws(AppRefusal) -> String {
        let note = text.trimmingCharacters(in: .whitespacesAndNewlines)
        try change { review in review.note = note }
        return note
    }

    /// Cmd+Return and `send`: every queued message of the open video goes
    /// out as one send, which the listener's `wait` gets, now or when it
    /// next opens. Words still in the popover are queued first, so nothing
    /// is left behind. Refused when nothing is queued.
    func sendQueue() async throws(AppRefusal) -> StateReport.Send {
        try needVideo()
        // A message whose pictures are still being written joins the send.
        await committing?.value
        if let draft, Self.hasWords(draft.text), review?.thread(atFrame: draft.time)?.openQuestion != nil {
            // Words to an open question are an answer, never in the queue.
            closePopover(.clickOutside)
        } else if let draft, Self.hasWords(draft.text) {
            self.draft = nil
            do throws(AppRefusal) {
                _ = try await queueMessage(text: draft.text, time: draft.time, region: draft.region, thread: nil)
            } catch {
                // The words aren't lost: the popover opens again with them.
                if self.draft == nil { self.draft = draft }
                throw error
            }
        }
        // The composer's words are queued, or answer at once, as Return
        // would take them; its draft stays when they are refused.
        if Self.hasWords(composerText) {
            _ = try await writeComposer()
        }
        guard let info = review?.video else { throw Self.noVideo }
        // Each thread's transcript window is cut now and kept with the send.
        let send = try change { [transcripts] review throws(ReviewRefusal) in
            try review.send(at: Date()) { thread in thread.time.map { transcripts.lines(around: $0, of: info) } ?? [] }
        }
        guard let video, let review = review else { throw Self.noVideo }
        let ref = SendRef(sendID: send.id, contentHash: video.contentHash)
        let listener = data.listeners.queue(ofVideo: video.contentHash)
        listener.enqueue(ref)
        // With nobody there, the send waits in the outbox and the Connect
        // view says so (G8).
        if listener.presence(at: Date()) == .absent { sentWithNoAgent(ref) }
        return StateReport.Send(send, in: review)
    }

    /// The answer field and `thread answer`: the person's answer to the
    /// open question on a thread. The `ask` that waits for it exits with it.
    func answer(_ thread: String, text: String) throws(AppRefusal) -> (message: StateReport.Message, number: Int) {
        let (id, hash) = try desk.threadID(thread, open: video?.contentHash)
        let message = try desk.change(hash) { review throws(ReviewRefusal) in try review.answer(id, text: text, now: Date()) }
        let report = StateReport.Message(message, contentHash: hash, layout: layout)
        data.listeners.queue(ofVideo: hash).answered(id, with: report)
        notices.removeAll { $0.thread == id && $0.kind == .question }
        return (report, id.number)
    }

    /// A quick-reply button and `thread choose`: the open question on a
    /// thread answered with its choice `number` (from 1), at once.
    func choose(_ thread: String, choice number: Int) throws(AppRefusal) -> (message: StateReport.Message, number: Int) {
        let (id, hash) = try desk.threadID(thread, open: video?.contentHash)
        guard let review = desk.review(of: hash) else { throw AppRefusal(ReviewRefusal.unknownID(thread).line) }
        let words: String
        do throws(ReviewRefusal) {
            words = try review.choice(number, on: id)
        } catch {
            throw AppRefusal(error.line)
        }
        return try answer(id.text, text: words)
    }

    /// `state`: what this window shows, with every window.
    func state() -> StateReport {
        let hash = video?.contentHash ?? ""
        let review = self.review
        var report = StateReport(
            app: app.appReport,
            video: video.map {
                .init(
                    path: $0.url.path, contentHash: $0.contentHash, title: $0.title, duration: engine.duration,
                    contextNote: contextNote
                )
            },
            player: .init(time: engine.time, playing: engine.isPlaying),
            popover: draft.map { .init(thread: draftThreadNumber, time: $0.time, text: $0.text, region: $0.region) },
            threads: threads.map { StateReport.Thread($0, contentHash: hash, layout: layout) },
            queue: review?.queue.map(\.id.text) ?? [],
            sends: review.map { review in sends.map { StateReport.Send($0, in: review) } } ?? []
        )
        report.transcript = transcript
        report.listener = listener?.report(at: Date()) ?? .absent
        report.theme = themes.report
        report.setup = app.setupReport(for: self)
        report.config = app.config.report
        report.sidebar = sidebarReport
        report.recents = recents
        report.screen = screen
        report.window = id
        report.windows = app.windowList()
        return report
    }

    /// What the window shows: the player, or home.
    var screen: StateReport.Screen {
        StageContent(hasVideo: video != nil, hasRecents: !recents.isEmpty).screen
    }

    /// The window as `window list` and `state` list it.
    func report(isKey: Bool) -> StateReport.Window {
        StateReport.Window(
            id: id, key: isKey, onScreen: nsWindow?.isVisible ?? false, screen: screen,
            video: video.map { StateReport.Window.Held(path: $0.url.path, title: $0.title, contentHash: $0.contentHash) },
            listener: listener.map { listener in
                let heard = listener.report(at: Date())
                return StateReport.Window.Heard(presence: heard.presence, session: heard.session)
            }
        )
    }

    /// Runs `change` on the open video's review, saves and publishes the
    /// result. Refused with no video.
    private func change<Result>(_ change: (inout VideoReview) throws(ReviewRefusal) -> Result) throws(AppRefusal) -> Result {
        guard let video else { throw Self.noVideo }
        return try desk.change(video.contentHash, change)
    }

    // MARK: - Messages

    /// Writes the pictures a message needs, then queues it. A thread's
    /// keyframe and a region's crop exist before the message does, so the
    /// listener never gets one without its pictures. The pictures are
    /// written under names of their own and take the ids the review gives
    /// once it has the message, so a message written meanwhile (a
    /// listener's reply) can't take their place.
    private func queueMessage(
        text: String, time: Double?, region: Region?, thread: ThreadID?
    ) async throws(AppRefusal) -> VideoReview.Written {
        // The message and its pictures stay on the data its video is on,
        // also when the run switches to other data meanwhile.
        let (desk, layout) = (self.desk, self.layout)
        guard let video, let asset = engine.asset, var trial = review else { throw Self.noVideo }
        // What the write will do, refused before any picture is written.
        let planned: VideoReview.Written
        do throws(ReviewRefusal) {
            planned = try trial.write(text: text, at: time, region: region, to: thread, now: Date())
        } catch {
            throw AppRefusal(error.line)
        }
        let hash = video.contentHash
        let token = UUID().uuidString
        let pendingKeyframe = planned.startedThread ? layout.pendingImage("\(token)-keyframe", of: hash) : nil
        let pendingCrop = region == nil ? nil : layout.pendingImage("\(token)-crop", of: hash)
        if let frame = planned.thread.time, pendingKeyframe != nil || pendingCrop != nil {
            try await FrameGrabber.writeImages(
                of: asset, at: frame, duration: engine.duration, frameDuration: engine.frameDuration,
                keyframe: pendingKeyframe, region: region, crop: pendingCrop
            )
        }
        defer {
            // Whatever wasn't moved into place isn't needed.
            if let pendingKeyframe { ImageFiles.remove(pendingKeyframe) }
            if let pendingCrop { ImageFiles.remove(pendingCrop) }
        }
        guard self.video == video else { throw AppRefusal("another video opened before the message was queued") }
        let written = try desk.change(hash) { review throws(ReviewRefusal) in
            try review.write(text: text, at: time, region: region, to: thread, now: Date())
        }
        let keyframe = layout.keyframe(written.thread.id, of: hash)
        if !written.thread.isGeneral, !FileManager.default.fileExists(atPath: keyframe.path) {
            if let pendingKeyframe {
                try? FileManager.default.moveItem(at: pendingKeyframe, to: keyframe)
            } else if let frame = written.thread.time {
                // The thread it was to join went meanwhile; this one gets its keyframe now.
                try? await FrameGrabber.writeImages(
                    of: asset, at: frame, duration: engine.duration, frameDuration: engine.frameDuration,
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
                // A region message never stays without its crop.
                _ = try? desk.change(hash) { review throws(ReviewRefusal) in try review.delete(written.message.id) }
                throw AppRefusal("couldn't keep the crop of the region: \(error.localizedDescription)")
            }
        }
        // A pin is picked out only while its video is still the open one.
        if self.video == video { selection = written.thread.id }
        return written
    }

    private func report(_ message: Message) -> StateReport.Message {
        StateReport.Message(message, contentHash: video?.contentHash ?? "", layout: layout)
    }

    /// The keyframe PNG of `thread` on the open video; nil for General.
    func keyframe(of thread: ReviewThread) -> URL? {
        video.flatMap { layout.keyframe(of: thread, on: $0.contentHash) }
    }

    /// The PNG of `message`'s region on the open video; nil for a message
    /// on the whole frame.
    func crop(of message: Message) -> URL? {
        video.flatMap { layout.crop(of: message, on: $0.contentHash) }
    }

    /// The threads on the frame on screen, paused or playing: each one's
    /// region outlines and number badge (D 2.6). Once the video moves on,
    /// the frame isn't the one they were written on, and they go.
    var frameMarks: [FrameMark] {
        guard video != nil else { return [] }
        let frame = engine.frameTime(of: engine.time)
        // A thousandth of a second: thread times are kept in milliseconds.
        return frameThreads.compactMap { thread in
            guard let time = thread.time, abs(time - frame) < 0.0005 else { return nil }
            return FrameMark(
                thread: thread.id, number: thread.number, state: thread.state ?? .queued,
                regions: thread.messages.compactMap(\.region)
            )
        }
    }

    /// The number of the thread the popover writes to: the thread of its
    /// frame, or the number a new thread will take (D 2.1). Nil while the
    /// popover is closed.
    var draftThreadNumber: Int? {
        guard let draft, let review = review else { return nil }
        return review.thread(atFrame: draft.time)?.number ?? review.nextThreadNumber
    }

    // MARK: - What an action needs

    private static let noVideo = AppRefusal("no video is open in the window; open one with `havooch player open <path>`")

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

    // MARK: - The person's gestures

    /// Space, K, a click on the frame, the play button. Play is a change
    /// of the moment: the popover closes by its rules first.
    func togglePlay() {
        guard video != nil else { return }
        if engine.isPlaying {
            engine.pause()
        } else {
            closePopover(.momentChanged)
            engine.play()
        }
    }

    /// Left, Right, J and L: `seconds` back or forward, kept inside the video.
    func skip(by seconds: Double) {
        move(to: engine.time + seconds)
    }

    /// Shift+Left, Shift+Right, comma and period: `frames` back or forward.
    func step(frames: Int) {
        engine.pause()
        move(to: engine.time + Double(frames) * engine.frameDuration)
    }

    /// The player bar's speed menu.
    func setSpeed(_ speed: Double) {
        engine.speed = speed
    }

    /// A drag on the scrubber, to `seconds`.
    func scrub(to seconds: Double) {
        move(to: seconds)
    }

    /// Every move of the person's: a change of the moment, so the popover
    /// closes by its rules before the player moves (D 2.2, D 2.3).
    private func move(to seconds: Double) {
        guard video != nil else { return }
        closePopover(.momentChanged)
        let target = min(max(seconds, 0), engine.duration)
        Task { await engine.seek(to: target) }
    }

    /// C, Return and the Comment button: pauses and opens the popover at
    /// the frame on screen. With `region`, the rectangle the person drew:
    /// the popover opens on that region. C with the popover open changes
    /// nothing; a new region closes the open popover as a click outside it
    /// does, and opens on the region.
    func startDraft(region: Region? = nil) {
        guard video != nil else { return }
        if draft != nil {
            guard region != nil else { return }
            closePopover(.clickOutside)
        }
        engine.pause()
        let time = engine.frameTime(of: engine.time)
        draft = Draft(time: time, text: "", region: region)
        // The region is the composer's chip too, until words take it (L41).
        if let region { drawnRegion = Draft(time: time, text: "", region: region) }
    }

    /// Closes the popover by `reason` (D 1.4, D 2.3): a click outside and
    /// a change of the moment queue its words at its own frame and region;
    /// the × and Escape drop them. A popover with no words only closes, and
    /// its region goes with it. With no popover it does nothing.
    func closePopover(_ reason: PopoverClose) {
        guard let draft else { return }
        self.draft = nil
        // Escape and the × drop the region the popover opened on, in the composer too.
        if reason == .discard { dropDrawnRegion(draft) }
        guard reason != .discard, Self.hasWords(draft.text) else { return }
        deliver(draft)
    }

    /// The drawn region goes from the composer when `draft` took or
    /// dropped it.
    private func dropDrawnRegion(_ draft: Draft) {
        guard let region = draft.region, drawnRegion?.region == region, drawnRegion?.time == draft.time else { return }
        drawnRegion = nil
    }

    /// The popover's words go on their thread: an answer at once while the
    /// thread has an open question (L14), else into the queue.
    private func deliver(_ draft: Draft) {
        // The words take the region: it isn't the composer's any more.
        dropDrawnRegion(draft)
        guard let thread = review?.thread(atFrame: draft.time), thread.openQuestion != nil else {
            queue(draft)
            return
        }
        // The words aren't lost: the popover holds them again.
        if !answerQuestion(thread.id, text: draft.text), self.draft?.text.isEmpty != false {
            self.draft = draft
        }
    }

    /// A click on the frame: plays or pauses. While the popover is open it
    /// is a click outside the popover, which closes it and leaves the
    /// video still.
    func clickFrame() {
        if draft == nil { togglePlay() } else { closePopover(.clickOutside) }
    }

    /// The pointer starts to drag on the frame: the video pauses, so the
    /// rectangle is drawn on a still frame. An open popover closes, as a
    /// click outside it does.
    func beginRegion() {
        guard video != nil else { return }
        closePopover(.clickOutside)
        engine.pause()
        isDrawingRegion = true
    }

    /// The pointer lets go: the popover opens on `region`. A drag that
    /// Escape cancelled, or one too small to be a region (nil), opens
    /// nothing.
    func endRegion(_ region: Region?) {
        guard isDrawingRegion else { return }
        isDrawingRegion = false
        if let region { startDraft(region: region) }
    }

    /// Escape: drops the rectangle being drawn, else the popover's words
    /// with its region, else goes back from a thread view or the Connect
    /// view to the thread list. False when there was none of them.
    @discardableResult
    func escape() -> Bool {
        if isDrawingRegion {
            isDrawingRegion = false
            return true
        }
        if draft != nil {
            closePopover(.discard)
            return true
        }
        guard shown != nil || connect != nil, isSidebarVisible else { return false }
        if connect != nil {
            // Back from the Connect view goes where it came from.
            closeConnect()
            return true
        }
        _ = showThreadList()
        return true
    }

    /// Return in the popover and its Queue or Answer button: the words go
    /// on the thread of the popover's frame, as an answer at once when the
    /// thread has an open question, else into the queue (L14). The popover
    /// stays open on its thread with an empty field, so the message shows
    /// in its conversation; a follow-up is on the whole frame. A popover
    /// with no words does nothing.
    func commitDraft() {
        guard let draft, Self.hasWords(draft.text) else { return }
        self.draft = Draft(time: draft.time, text: "", region: nil)
        deliver(draft)
    }

    /// The thread the popover writes to, once it has one: the thread of
    /// its frame. Nil for a popover that will start a thread, and while
    /// it's closed.
    var draftThread: ReviewThread? {
        guard let draft else { return nil }
        return review?.thread(atFrame: draft.time)
    }

    /// A click on a thread's pin or its badge: the player pauses on the
    /// thread's frame, and the thread popover opens there, at the frame the
    /// person left it at (D 2.6 to D 2.10). The move to the frame is a
    /// change of the moment for a popover open on another frame; one open
    /// on this thread stays as it is. General has no frame to open on.
    func openThread(_ id: ThreadID) {
        guard let time = startThread(id) else { return }
        Task { await engine.seek(to: time) }
    }

    /// `thread open`: the thread popover opens as a click on the thread's
    /// pin opens it, once the player is on its frame. With `frame`, the
    /// popover is first kept at that frame, as a drag and a resize leave it.
    func openThread(_ ref: String, frame: PopoverFrame?) async throws(AppRefusal) -> StateReport.Popover {
        try needVideo()
        let (id, hash) = try desk.threadID(ref, open: video?.contentHash)
        guard hash == video?.contentHash else { throw AppRefusal(ReviewRefusal.otherVideo(id.text).line) }
        guard review?.thread(id)?.isGeneral == false else {
            throw AppRefusal("General has no frame to open a popover on; its messages are in the sidebar")
        }
        if let frame { try movePopover(id, to: frame) }
        guard let time = startThread(id) else { throw Self.noVideo }
        await committing?.value
        await engine.seek(to: time)
        guard let popover = state().popover else { throw Self.noVideo }
        return popover
    }

    /// Opens the popover on thread `id`'s frame and pauses: the frame time
    /// the player goes to, or nil for General or a thread that's gone.
    private func startThread(_ id: ThreadID) -> Double? {
        guard let thread = review?.thread(id), let time = thread.time else { return nil }
        selection = id
        // The sidebar shows the same conversation as the popover (L38).
        shown = id
        engine.pause()
        if draft?.time != time {
            closePopover(.momentChanged)
            draft = Draft(time: time, text: "", region: nil)
        }
        return time
    }

    /// `comment open`: the popover opens at the player's frame, on
    /// `region` when there is one, with `text` in its field, as C or a
    /// drawn rectangle opens it. An open popover closes first, as a click
    /// outside it does.
    func openPopover(text: String, region: Region?) throws(AppRefusal) -> StateReport.Popover {
        try needVideo()
        closePopover(.clickOutside)
        startDraft(region: region)
        draft?.text = text
        guard let popover = state().popover else { throw Self.noVideo }
        return popover
    }

    /// Queues the popover's words in a task, after the ones before it, so
    /// the popover closes at once while the pictures are written.
    private func queue(_ draft: Draft) {
        let before = committing
        commitsUnderWay += 1
        committing = Task {
            defer { commitsUnderWay -= 1 }
            await before?.value
            do throws(AppRefusal) {
                _ = try await queueMessage(text: draft.text, time: draft.time, region: draft.region, thread: nil)
            } catch {
                // The words aren't lost: the popover holds them again.
                if self.draft?.text.isEmpty != false { self.draft = draft }
                problem = Problem(title: "The message wasn't queued", reason: error.reason)
            }
        }
    }

    /// Cmd+Return and the Send button: sends the queue, with the words in
    /// the popover. With nothing to send it does nothing.
    func send() {
        // An answer in the composer goes at once, as Return takes it, even
        // with nothing queued to send after it.
        if let target = composerTarget, target.answers, let thread = target.thread, Self.hasWords(composerText) {
            let text = composerText
            if answerQuestion(thread, text: text) { spendComposer(target, text: text) }
        }
        // A second press while the first is on its way has nothing to add.
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

    // MARK: - The sidebar

    /// A click on a row of the thread list, Previous and Next, Up and
    /// Down: the sidebar shows the thread's view, its pin is picked out,
    /// and the player pauses on its frame. General has no frame to move
    /// to. A move to the thread's frame is a change of the moment.
    func showThread(_ id: ThreadID) {
        guard let thread = show(id) else { return }
        if let time = thread.time { move(to: time) }
    }

    /// `thread show` (L39): the sidebar shows the thread's view, as a
    /// click on its row does. It answers once the player is on the
    /// thread's frame, so `state` after it shows the frame.
    func showThread(_ ref: String) async throws(AppRefusal) -> (sidebar: StateReport.Sidebar, number: Int) {
        try needVideo()
        let (id, hash) = try desk.threadID(ref, open: video?.contentHash)
        guard hash == video?.contentHash, let thread = show(id) else {
            throw AppRefusal(ReviewRefusal.otherVideo(id.text).line)
        }
        if let time = thread.time {
            closePopover(.momentChanged)
            await committing?.value
            await engine.seek(to: time)
        }
        return (sidebarReport, id.number)
    }

    /// Shows thread `id`'s view, picks out its pin and pauses: the
    /// thread, or nil for one the open video doesn't have.
    private func show(_ id: ThreadID) -> ReviewThread? {
        guard let thread = review?.thread(id) else { return nil }
        selection = id
        shown = id
        engine.pause()
        return thread
    }

    /// The person sees thread `id`'s view now: its agent messages until
    /// now are read, and its row loses the unread dot (L46). Nothing for
    /// a thread the open video doesn't have.
    private func markSeen(_ id: ThreadID) {
        guard review?.thread(id) != nil else { return }
        _ = try? change { review throws(ReviewRefusal) in try review.markSeen(id, at: Date()) }
    }

    /// Whether a control has the keyboard focus, so Space and Return
    /// press it and don't reach the player.
    var isControlFocused: Bool { !focusedControls.isEmpty }

    /// The control `id` took the keyboard focus; Space and Return now
    /// call `press`, as a click does.
    func focusControl(_ id: UUID, press: @escaping () -> Void) {
        focusedControls.removeAll { $0.id == id }
        focusedControls.append((id, press))
    }

    /// The control `id` lost the keyboard focus, or left the window. A
    /// control that took the focus since keeps it; else the one that had
    /// it before and still has it gets it back.
    func blurControl(_ id: UUID) {
        focusedControls.removeAll { $0.id == id }
    }

    /// Presses the control that has the keyboard focus; false when none has.
    @discardableResult
    func pressFocusedControl() -> Bool {
        guard let control = focusedControls.last else { return false }
        control.press()
        return true
    }

    /// A row's action on thread `id`: the one path for a click, Space or
    /// Return on the focused row, the row's menu and VoiceOver.
    func perform(_ action: RowAction, on id: ThreadID) {
        switch action {
        case .open: showThread(id)
        case .showOnVideo: showOnVideo(id)
        case .deleteQueued: deleteQueued(on: id)
        }
    }

    /// What a row's menu offers for `thread` (L40): Open always; Show on
    /// video when it has a frame; Delete queued messages when it has any.
    func rowActions(for thread: ReviewThread) -> [RowAction] {
        var actions: [RowAction] = [.open]
        if !thread.isGeneral { actions.append(.showOnVideo) }
        if thread.messages.contains(where: { $0.state == .queued }) { actions.append(.deleteQueued) }
        return actions
    }

    /// Show on video in a row's menu: the thread's pin is picked out and
    /// the player pauses on its frame (a change of the moment); the sidebar
    /// stays on the list. General has no frame.
    func showOnVideo(_ id: ThreadID) {
        guard let thread = review?.thread(id), let time = thread.time else { return }
        selection = id
        engine.pause()
        move(to: time)
    }

    /// Delete queued messages in a row's menu: each queued message of the
    /// thread goes, as its own Delete would take it; a thread left with no
    /// message goes too. A sent message stays.
    func deleteQueued(on id: ThreadID) {
        let queued = review?.thread(id)?.messages.filter { $0.state == .queued }.map(\.id) ?? []
        for message in queued { delete(message) }
    }

    /// Back, Escape and `thread list`: the sidebar shows the thread list.
    /// The player stays where it is.
    func showThreadList() -> StateReport.Sidebar {
        shown = nil
        connect = nil
        return sidebarReport
    }

    /// Previous and Next in a thread view: the thread before or after the
    /// one shown, in the list's time order (General first). Nothing at
    /// either end.
    func showNeighbour(forward: Bool) {
        guard let next = neighbour(forward: forward) else { return }
        showThread(next.id)
    }

    /// The thread Previous (`forward` false) or Next shows; nil at either
    /// end, and in the thread list.
    func neighbour(forward: Bool) -> ReviewThread? {
        let threads = threads
        guard let shown, let index = threads.firstIndex(where: { $0.id == shown }) else { return nil }
        let next = index + (forward ? 1 : -1)
        return threads.indices.contains(next) ? threads[next] : nil
    }

    /// The thread list's groups (`ThreadGroup`), in their order, each with
    /// its threads in time order; an empty group isn't there.
    var threadGroups: [ThreadGroup.Section] { ThreadGroup.sections(of: threads) }

    /// How many threads need the person (an open question) besides the
    /// one the sidebar shows: the count on Back.
    var othersNeedingYou: Int {
        threads.filter { $0.openQuestion != nil && $0.id != shown }.count
    }

    /// The thread whose frame is on the stage: its row in the list sits in
    /// a `well`. Nil off every thread's frame.
    var stageThread: ThreadID? {
        frameMarks.first?.thread
    }

    /// The sidebar as `state` reports it: the thread it shows, its width
    /// and the composer.
    var sidebarReport: StateReport.Sidebar {
        var report = StateReport.Sidebar(thread: shown?.text, width: Double(sidebarWidth), composer: composerReport)
        report.mode = connect != nil ? "connect" : shown != nil ? "thread" : "threads"
        report.connect = connectReport
        return report
    }

    // MARK: - The composer at the sidebar's foot (L41)

    /// Where the composer's words go now; nil with no video.
    var composerTarget: ComposerTarget? {
        guard video != nil, let review = review else { return nil }
        let frame = engine.frameTime(of: engine.time)
        let shownThread = shown.flatMap { review.thread($0) }
        return ComposerTarget.resolve(
            shown: shownThread,
            general: shownThread == nil && isComposerGeneral ? threads.first(where: \.isGeneral) : nil,
            atFrame: review.thread(atFrame: frame),
            frame: frame,
            nextNumber: review.nextThreadNumber,
            // The region counts while the stage shows the frame it was drawn on.
            regionTime: drawnRegion.map(\.time).flatMap { $0 == frame ? $0 : nil }
        )
    }

    /// Whether the person points at a region: draws a rectangle, or has a
    /// drawn one in the composer. The quick replies hide meanwhile.
    var isPointingAtRegion: Bool { isDrawingRegion || composerRegion != nil }

    /// The region chip in the composer: the drawn region, when it goes
    /// with the words.
    var composerRegion: Region? {
        guard composerTarget?.takesRegion == true else { return nil }
        return drawnRegion?.region
    }

    /// The words in the composer: the draft of its target.
    var composerText: String {
        get { composerTarget.flatMap { composerDrafts[$0.draftKey] } ?? "" }
        set {
            guard let key = composerTarget?.draftKey else { return }
            composerDrafts[key] = newValue.isEmpty ? nil : newValue
        }
    }

    /// The General toggle in the thread list.
    func toggleComposerGeneral() {
        isComposerGeneral.toggle()
    }

    /// The × on the composer's region chip: the words go on the whole frame.
    func removeComposerRegion() {
        drawnRegion = nil
    }

    /// The person clicked into the composer: the player pauses, so the
    /// frame it writes at holds still.
    func composerBegan() {
        engine.pause()
    }

    /// Return in the composer and its button: the words go to the target,
    /// an answer at once, else into the queue. The draft empties once
    /// they are written; when they are refused the person is told why.
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

    /// Writes the composer's words to its target: the target's kind,
    /// once they are written. The draft, the region chip and the General
    /// toggle are spent; the sidebar stays where it is.
    @discardableResult
    func writeComposer() async throws(AppRefusal) -> ComposerTarget.Kind {
        guard let target = composerTarget else { throw Self.noVideo }
        let text = composerText
        try needWords(text)
        if target.answers, let thread = target.thread {
            _ = try answer(thread.text, text: text)
        } else {
            let region = target.takesRegion ? drawnRegion?.region : nil
            engine.pause()
            _ = try await queueMessage(text: text, time: target.isGeneral ? nil : target.time, region: region, thread: target.thread)
            if region != nil, drawnRegion?.region == region { drawnRegion = nil }
        }
        spendComposer(target, text: text)
        return target.kind
    }

    /// The composer's `text` went to `target`: its draft goes, unless the
    /// person typed on meanwhile, and the General toggle goes off.
    private func spendComposer(_ target: ComposerTarget, text: String) {
        if composerDrafts[target.draftKey] == text { composerDrafts[target.draftKey] = nil }
        if target.isGeneral { isComposerGeneral = false }
    }

    /// `comment compose` (L41): the words in the composer and its region
    /// chip, as the person types them and draws, with the General toggle
    /// on or off. The composer's field takes the keys. The region is on the
    /// frame on the stage.
    func compose(text: String, region: Region?, general: Bool) throws(AppRefusal) -> StateReport.Sidebar.Composer {
        try needVideo()
        engine.pause()
        isComposerGeneral = general
        if let region {
            drawnRegion = Draft(time: engine.frameTime(of: engine.time), text: "", region: region)
        }
        composerText = text
        composerFocusRequests += 1
        guard let report = composerReport else { throw Self.noVideo }
        return report
    }

    /// The composer as `state` reports it.
    var composerReport: StateReport.Sidebar.Composer? {
        guard let target = composerTarget else { return nil }
        return StateReport.Sidebar.Composer(
            target: target.line, kind: target.kind.name, thread: target.thread?.text, number: target.number, time: target.time,
            general: isComposerGeneral && shown == nil, text: composerText, region: composerRegion
        )
    }

    /// The sidebar's width: the app's, the same in every window.
    var sidebarWidth: CGFloat { app.sidebarWidth }

    /// `kept` inside `Metrics.sidebarWidthRange`; the default with none.
    static func sidebarWidth(kept: Double?) -> CGFloat {
        guard let kept, kept.isFinite else { return Metrics.sidebarWidth }
        let range = Metrics.sidebarWidthRange
        return min(max(CGFloat(kept), range.lowerBound), range.upperBound)
    }

    /// The person let go of the sidebar's edge at `width`: it is kept for
    /// every window (`AppModel.keepSidebarWidth`).
    func keepSidebarWidth(_ width: CGFloat) {
        app.keepSidebarWidth(width)
    }

    /// Up and Down: the pin before or after the player's time.
    func jumpToMarker(forward: Bool) {
        // Half a frame: the pin the player stands on isn't its own neighbour.
        let slack = engine.frameDuration / 2
        let pinned = frameThreads
        let next = forward
            ? pinned.first { ($0.time ?? 0) > engine.time + slack }
            : pinned.last { ($0.time ?? 0) < engine.time - slack }
        if let next { showThread(next.id) }
    }

    // MARK: - What the agent says

    /// The agent's name as the threads and the notices show it: the
    /// listener's, or "Agent" before anyone listened.
    var agentName: String { listener?.outbox.session?.name ?? "Agent" }

    /// The agent harness the listener's name says, for its logo; nil before
    /// anyone listened, or for a name no known agent has.
    var agent: KnownAgent? { listener?.outbox.session?.agent }

    /// The agent said something: a notice goes up on the stage. Every
    /// notice goes by itself; a question stays open on its thread.
    func raise(_ notice: Notice) {
        // The thread view shows the message as it comes: it's read.
        if notice.thread == shown { markSeen(notice.thread) }
        notices.append(notice)
        let expires = notice.expires
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(expires.timeIntervalSinceNow, 0)))
            self?.dismiss(notice.id)
        }
    }

    /// The notice `id` goes: its time is up.
    func dismiss(_ id: UUID) {
        notices.removeAll { $0.id == id }
    }

    /// A click on a notice: it goes, and its thread's popover opens on
    /// the thread's frame, with the answer field under a question (D 4.10).
    /// A notice on General shows General's thread view (L18).
    func openNotice(_ id: UUID) {
        guard let notice = notices.first(where: { $0.id == id }) else { return }
        dismiss(id)
        // General has no frame: its conversation is in the sidebar (L18).
        if notice.thread.number == 0 {
            isSidebarVisible = true
            shown = notice.thread
        } else {
            openThread(notice.thread)
        }
    }

    /// Return in an answer field and its button: the person's answer to
    /// the thread's open question. False when it wasn't taken.
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

    /// A click on a quick-reply button: the open question on `thread`
    /// answered with its choice `number` (from 1). False when it wasn't
    /// taken.
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

    /// Save on a row: the message's new text.
    func edit(_ id: MessageID, text: String) {
        do throws(AppRefusal) {
            _ = try editMessage(id.text, text: text)
        } catch {
            problem = Problem(title: "The message didn't change", reason: error.reason)
        }
    }

    /// Delete on a row.
    func delete(_ id: MessageID) {
        do throws(AppRefusal) {
            _ = try deleteMessage(id.text)
        } catch {
            problem = Problem(title: "The message wasn't deleted", reason: error.reason)
        }
    }

    // MARK: - The video context

    /// The open video's context note; empty for none.
    var contextNote: String { review?.note ?? "" }

    /// The context the listener is told about the open video, as the
    /// popover last read it: the sidecar's text, then the note.
    var contextText: String? {
        ContextReader.text(sidecar: sidecar?.text, note: contextNote)
    }

    /// Whether the listener's next send of the open video carries the
    /// context: there is one, and this listener session hasn't had it.
    var isContextDue: Bool {
        guard let video else { return false }
        return listener?.outbox.isContextDue(for: video.contentHash, text: contextText) ?? false
    }

    /// The context popover opens: the sidecar is read again, since nothing
    /// watches the file.
    func readSidecar() {
        sidecar = video.flatMap { ContextReader.sidecar(beside: $0.url) }
    }

    /// Save in the context popover: the note goes the way `context set`
    /// goes, and the popover closes.
    func saveContextNote(_ text: String) {
        do throws(AppRefusal) {
            try setContextNote(text)
            isContextShown = false
        } catch {
            problem = Problem(title: "The note wasn't saved", reason: error.reason)
        }
    }

    /// Cmd+O and the Open button: the file the person picks, opened in
    /// this window unless another one holds it.
    func openFromPanel() {
        app.openFromPanel(from: self)
    }

    /// Opens `url` for the person, who is shown why when it doesn't play:
    /// the window that holds it comes forward, else this window opens it.
    /// The Open panel and a drop open the person's video on their own
    /// data: an in-app demo is left first.
    func openForPerson(_ url: URL) {
        app.openForPerson(url, from: self)
    }
}
