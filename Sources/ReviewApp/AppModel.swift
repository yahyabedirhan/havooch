import AppKit
import Observation
import ReviewCore
import ReviewLease
import ReviewStore
import ReviewTranscript
import ReviewWire
import UniformTypeIdentifiers

/// The orchestrator: which video is open, the message being written, the
/// selected thread, and every action a person or an operator can take. The
/// UI and the control server call the same methods, so a click and its CLI
/// command are one code path.
@Observable
final class AppModel: AppControlling {
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

    let engine = PlayerEngine()
    /// The open video's review, and the one path for changing it.
    let desk: ReviewDesk
    /// The listener's side: the sends in line and whether an agent is
    /// there for them.
    let listeners: ListenerQueue
    /// The transcripts of the videos opened in this run.
    let transcripts: TranscriptDesk
    /// The active theme, the pin and the overrides.
    let themes: ThemeDesk
    /// Where this run keeps its data: the person's own, or a demo's.
    let support: URL
    /// Whether this run is on demo data (`app open --demo`).
    let isDemo: Bool
    private(set) var video: OpenVideo?
    /// The message being written; nil while the popover is closed.
    var draft: Draft?
    /// The thread whose pin is picked out.
    private(set) var selection: ThreadID?
    /// The thread the sidebar shows in its thread view; nil while it
    /// shows the thread list (L38). Showing a thread's view marks its
    /// agent messages read (L46).
    private(set) var shown: ThreadID? {
        didSet { if let shown { markSeen(shown) } }
    }
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

    /// Shows the player's window when it's closed; the app sets it.
    @ObservationIgnored var showWindow: () -> Void = {}

    @ObservationIgnored private let layout: SupportLayout
    /// The message the popover is queueing: its pictures are being
    /// written. A send waits for it.
    @ObservationIgnored private var committing: Task<Void, Never>?
    /// How many messages from the popover are on their way into the queue.
    private var commitsUnderWay = 0
    /// Whether a send the person asked for is on its way.
    @ObservationIgnored private var isSending = false

    /// The files the Open panel offers: what the spec names.
    static let videoTypes: [UTType] = [.mpeg4Movie, .quickTimeMovie, UTType("com.apple.m4v-video")].compactMap(\.self)

    /// `speech` turns a video's sound into lines when it has no sidecar;
    /// tests give their own.
    init(environment: [String: String], speech: any SpeechRecognizing = AppleSpeechRecognizer()) {
        support = SupportFolder.app(environment: environment)
        isDemo = SupportFolder.moved(environment: environment) != nil
        layout = SupportLayout(root: support)
        desk = ReviewDesk(library: Library(layout: layout))
        listeners = ListenerQueue(desk: desk, layout: layout)
        transcripts = TranscriptDesk(layout: layout, speech: speech)
        themes = ThemeDesk(layout: layout)
        listeners.announce = { [weak self] notice in self?.raise(notice) }
    }

    /// The open video's transcript as `state` and the Context popover show
    /// it: its source, and how far it is.
    var transcript: StateReport.Transcript? {
        video.flatMap { transcripts.report(of: $0.contentHash) }
    }

    /// The open video's threads: General first, then in time order.
    var threads: [ReviewThread] { desk.review?.threads ?? [] }

    /// The open video's threads on a frame: every one but General.
    var frameThreads: [ReviewThread] { threads.filter { !$0.isGeneral } }

    /// The open video's sends, in the order they were sent.
    var sends: [Send] { desk.review?.sends ?? [] }

    /// Whether Cmd+Return has something to send: a queued message, one on
    /// its way into the queue, or words in the popover.
    var canSend: Bool {
        sendCount > 0
    }

    /// How many messages wait in the queue, as the sidebar's footer counts them.
    var queuedCount: Int { desk.review?.queue.count ?? 0 }

    /// How many messages a send would deliver now: the queue, with the
    /// words in the popover and in the composer that would join it.
    var sendCount: Int {
        let popover = draft.map { Self.hasWords($0.text) } == true ? 1 : 0
        let composer = composerTarget.map { !$0.answers && Self.hasWords(composerText) } == true ? 1 : 0
        return (desk.review?.queue.count ?? 0) + commitsUnderWay + popover + composer
    }

    // MARK: - Actions, for the person and the operator alike

    func open(_ url: URL) async throws(AppRefusal) {
        let url = url.standardizedFileURL
        var isFolder: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder), !isFolder.boolValue else {
            throw AppRefusal("no video file at \(url.path)")
        }
        guard let contentHash = await Self.contentHash(of: url) else {
            throw AppRefusal("can't read \(url.path)")
        }
        // Before the player changes: a history that doesn't read keeps the
        // video shut, and the one that was open stays open.
        // The file's name with its extension, the same in the header, the state and the payload.
        let title = url.lastPathComponent
        // Another video is a change of the moment: words in the popover are
        // queued on the video they were written on, before it goes.
        closePopover(.momentChanged)
        await committing?.value
        let found = try desk.review(for: VideoInfo(contentHash: contentHash, title: title, duration: 0, path: url.path))
        try await engine.load(url)
        // The review as it is now, not as it was before the load: a
        // listener may have answered on one of its threads meanwhile.
        var review = desk.review(of: contentHash) ?? found
        video = OpenVideo(url: url, title: title, contentHash: contentHash)
        draft = nil
        selection = nil
        shown = nil
        isDrawingRegion = false
        // The composer's words were on the video that was open.
        composerDrafts = [:]
        isComposerGeneral = false
        drawnRegion = nil
        // They point at threads of the video that was open.
        notices = []
        isContextShown = false
        sidecar = ContextReader.sidecar(beside: url)
        let frameRate = 1 / engine.frameDuration
        // The same content, where and as it is now: a renamed or moved copy
        // has its history, and the review records the new path.
        review.video = VideoInfo(
            contentHash: contentHash, title: title, duration: engine.duration, path: url.path, frameRate: frameRate
        )
        desk.open(review)
        desk.library.saveRecent(url)
        transcripts.opened(VideoFile(url: url, contentHash: contentHash, frameRate: frameRate, duration: engine.duration))
        // A control command's open is seen when the window was closed.
        showWindow()
    }

    /// The player's window closed; the app and this model stay. The video
    /// pauses, and the Dock icon shows it again where it was.
    func windowClosed() {
        engine.pause()
    }

    /// The hash of the file at `url`, read off the main actor: it reads the
    /// whole file, and a long video would hold the window still.
    @concurrent
    private nonisolated static func contentHash(of url: URL) async -> String? {
        ContentHash.of(url)
    }

    /// At launch: the video the launch names (`DemoRun.openVariable`, a
    /// demo started from the empty screen), else none. A launch never
    /// opens the last video by itself.
    func openAtLaunch(environment: [String: String]) async {
        guard let path = environment[DemoRun.openVariable], path.hasPrefix("/") else { return }
        do throws(AppRefusal) {
            try await open(URL(fileURLWithPath: path))
        } catch {
            problem = Problem(title: "The video didn't open", reason: error.reason)
        }
    }

    /// "Try the demo": the bundled sample video on demo data. A demo run
    /// opens it here; a run on the person's data starts a demo copy of the
    /// app and quits, so demo threads never mix with the person's.
    func tryDemo() {
        guard let video = DemoRun.video() else {
            problem = Problem(title: "The demo didn't open", reason: "this build has no bundled demo video; run `make bundle`")
            return
        }
        if isDemo {
            openForPerson(video)
            return
        }
        DemoRun.launch(video: video, normalSupport: support) { [weak self] reason in
            if let reason {
                self?.problem = Problem(title: "The demo didn't open", reason: reason)
            } else {
                NSApp.terminate(nil)
            }
        }
    }

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
        guard let review = desk.review else { throw Self.noVideo }
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
        let message = try desk.change { review throws(ReviewRefusal) in try review.edit(id, text: text) }
        return report(message)
    }

    /// `comment delete` and a row's Delete: a queued message goes, with its
    /// crop; a thread that loses its last message goes, with its keyframe.
    func deleteMessage(_ id: String) throws(AppRefusal) -> StateReport.Message {
        let id = try messageID(id)
        let deleted = try desk.change { review throws(ReviewRefusal) in try review.delete(id) }
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
        try desk.change { review throws(ReviewRefusal) in try review.setPopoverFrame(thread, frame) }
    }

    /// The context popover's Save and `context set`: the open video's
    /// context note, kept without the space around it. The listener gets
    /// it under the sidecar's text with the next send. An empty text clears
    /// the note.
    @discardableResult
    func setContextNote(_ text: String) throws(AppRefusal) -> String {
        let note = text.trimmingCharacters(in: .whitespacesAndNewlines)
        try desk.change { review in review.note = note }
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
        if let draft, Self.hasWords(draft.text), desk.review?.thread(atFrame: draft.time)?.openQuestion != nil {
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
        guard let info = desk.review?.video else { throw Self.noVideo }
        // Each thread's transcript window is cut now and kept with the send.
        let send = try desk.change { [transcripts] review throws(ReviewRefusal) in
            try review.send(at: Date()) { thread in thread.time.map { transcripts.lines(around: $0, of: info) } ?? [] }
        }
        guard let video, let review = desk.review else { throw Self.noVideo }
        listeners.enqueue(SendRef(sendID: send.id, contentHash: video.contentHash))
        return StateReport.Send(send, in: review)
    }

    /// The answer field and `thread answer`: the person's answer to the
    /// open question on a thread. The `ask` that waits for it exits with it.
    func answer(_ thread: String, text: String) throws(AppRefusal) -> (message: StateReport.Message, number: Int) {
        let (id, hash) = try desk.threadID(thread)
        let message = try desk.change(hash) { review throws(ReviewRefusal) in try review.answer(id, text: text, now: Date()) }
        let report = StateReport.Message(message, contentHash: hash, layout: layout)
        listeners.answered(id, with: report)
        notices.removeAll { $0.thread == id && $0.kind == .question }
        return (report, id.number)
    }

    /// A quick-reply button and `thread choose`: the open question on a
    /// thread answered with its choice `number` (from 1), at once.
    func choose(_ thread: String, choice number: Int) throws(AppRefusal) -> (message: StateReport.Message, number: Int) {
        let (id, hash) = try desk.threadID(thread)
        guard let review = desk.review(of: hash) else { throw AppRefusal(ReviewRefusal.unknownID(thread).line) }
        let words: String
        do throws(ReviewRefusal) {
            words = try review.choice(number, on: id)
        } catch {
            throw AppRefusal(error.line)
        }
        return try answer(id.text, text: words)
    }

    func state() -> StateReport {
        let hash = video?.contentHash ?? ""
        let review = desk.review
        var report = StateReport(
            app: .init(version: Version.app, demo: isDemo, support: support.path),
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
        report.theme = themes.report
        report.sidebar = sidebarReport
        return report
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
        guard let video, let asset = engine.asset, var trial = desk.review else { throw Self.noVideo }
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
        let written = try desk.change { review throws(ReviewRefusal) in
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
                _ = try? desk.change { review throws(ReviewRefusal) in try review.delete(written.message.id) }
                throw AppRefusal("couldn't keep the crop of the region: \(error.localizedDescription)")
            }
        }
        selection = written.thread.id
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
        guard let draft, let review = desk.review else { return nil }
        return review.thread(atFrame: draft.time)?.number ?? review.nextThreadNumber
    }

    // MARK: - What an action needs

    private static let noVideo = AppRefusal("no video is open; open one with `havooch player open <path>`")

    private func needVideo() throws(AppRefusal) {
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
        guard let thread = desk.review?.thread(atFrame: draft.time), thread.openQuestion != nil else {
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
    /// with its region, else goes back from a thread view to the thread
    /// list. False when there was none of them.
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
        guard shown != nil, isSidebarVisible else { return false }
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
        return desk.review?.thread(atFrame: draft.time)
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
        let (id, hash) = try desk.threadID(ref)
        guard hash == video?.contentHash else { throw AppRefusal(ReviewRefusal.otherVideo(id.text).line) }
        guard desk.review?.thread(id)?.isGeneral == false else {
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
        guard let thread = desk.review?.thread(id), let time = thread.time else { return nil }
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
        let (id, hash) = try desk.threadID(ref)
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
        guard let thread = desk.review?.thread(id) else { return nil }
        selection = id
        shown = id
        engine.pause()
        return thread
    }

    /// The person sees thread `id`'s view now: its agent messages until
    /// now are read, and its row loses the unread dot (L46). Nothing for
    /// a thread the open video doesn't have.
    private func markSeen(_ id: ThreadID) {
        guard desk.review?.thread(id) != nil else { return }
        _ = try? desk.change { review throws(ReviewRefusal) in try review.markSeen(id, at: Date()) }
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
        guard let thread = desk.review?.thread(id), let time = thread.time else { return }
        selection = id
        engine.pause()
        move(to: time)
    }

    /// Delete queued messages in a row's menu: each queued message of the
    /// thread goes, as its own Delete would take it; a thread left with no
    /// message goes too. A sent message stays.
    func deleteQueued(on id: ThreadID) {
        let queued = desk.review?.thread(id)?.messages.filter { $0.state == .queued }.map(\.id) ?? []
        for message in queued { delete(message) }
    }

    /// Back, Escape and `thread list`: the sidebar shows the thread list.
    /// The player stays where it is.
    func showThreadList() -> StateReport.Sidebar {
        shown = nil
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
        StateReport.Sidebar(thread: shown?.text, width: Double(sidebarWidth), composer: composerReport)
    }

    // MARK: - The composer at the sidebar's foot (L41)

    /// Where the composer's words go now; nil with no video.
    var composerTarget: ComposerTarget? {
        guard video != nil, let review = desk.review else { return nil }
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

    /// The sidebar's width: the kept one, inside the limits, else the
    /// default.
    var sidebarWidth: CGFloat { Self.sidebarWidth(kept: themes.settings.sidebarWidth) }

    /// `kept` inside `Metrics.sidebarWidthRange`; the default with none.
    static func sidebarWidth(kept: Double?) -> CGFloat {
        guard let kept, kept.isFinite else { return Metrics.sidebarWidth }
        let range = Metrics.sidebarWidthRange
        return min(max(CGFloat(kept), range.lowerBound), range.upperBound)
    }

    /// The person let go of the sidebar's edge at `width`: it is kept in
    /// the settings, inside the limits, for this run and the next.
    func keepSidebarWidth(_ width: CGFloat) {
        let width = Self.sidebarWidth(kept: Double(width.rounded()))
        guard width != sidebarWidth else { return }
        do throws(AppRefusal) {
            try themes.keepSidebarWidth(Double(width))
        } catch {
            // A width is a comfort, not the person's work: it's only lost.
        }
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
    var agentName: String { listeners.outbox.session?.name ?? "Agent" }

    /// The agent harness the listener's name says, for its logo; nil before
    /// anyone listened, or for a name no known agent has.
    var agent: KnownAgent? { listeners.outbox.session?.agent }

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
    var contextNote: String { desk.review?.note ?? "" }

    /// The context the listener is told about the open video, as the
    /// popover last read it: the sidecar's text, then the note.
    var contextText: String? {
        ContextReader.text(sidecar: sidecar?.text, note: contextNote)
    }

    /// Whether the listener's next send of the open video carries the
    /// context: there is one, and this listener session hasn't had it.
    var isContextDue: Bool {
        guard let video else { return false }
        return listeners.outbox.isContextDue(for: video.contentHash, text: contextText)
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

    /// Cmd+O and the Open button: the file the person picks.
    func openFromPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = Self.videoTypes
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose a video to review"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        openForPerson(url)
    }

    /// Opens `url` for the person, who is shown why when it doesn't play.
    func openForPerson(_ url: URL) {
        Task {
            do throws(AppRefusal) {
                try await open(url)
            } catch {
                problem = Problem(title: "The video didn't open", reason: error.reason)
            }
        }
    }
}
