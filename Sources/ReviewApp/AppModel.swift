import AppKit
import Observation
import ReviewCore
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

    /// The message still in the popover: view state only, never kept. It
    /// has a frame time, and no id and no keyframe until it's queued.
    struct Draft: Equatable {
        var time: Double
        var text: String
        /// The rectangle the person drew; nil for the whole frame.
        var region: Region?
    }

    /// A region drawn on the frame, and the thread it belongs to.
    struct ShownRegion: Equatable {
        var region: Region
        /// The thread's number, as on its pin; nil for the message still
        /// in the popover.
        var number: Int?
        /// The thread's state, which its pin is drawn by; nil for the
        /// message still in the popover.
        var state: MessageState?
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
    /// The thread whose pin and section are picked out.
    private(set) var selection: ThreadID?
    /// Whether the person is dragging a rectangle on the frame.
    private(set) var isDrawingRegion = false
    /// Whether the rail is shown beside the stage.
    var isRailVisible = true
    /// Whether the context popover is open.
    var isContextShown = false
    /// The open video's sidecar context file, as it was last read.
    private(set) var sidecar: ContextReader.Sidecar?
    /// Shown to the person until they dismiss it.
    var problem: Problem?
    /// What the agent just said, shown on the stage: the newest last.
    private(set) var notices: [Notice] = []
    /// The threads with an agent message the person hasn't looked at.
    private(set) var unread: Set<ThreadID> = []

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
        listeners.transcripts = transcripts
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

    /// How many messages a send would deliver now.
    var sendCount: Int {
        (desk.review?.queue.count ?? 0) + commitsUnderWay + (draft.map { Self.hasWords($0.text) } == true ? 1 : 0)
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
        let title = url.deletingPathExtension().lastPathComponent
        let found = try desk.review(for: VideoInfo(contentHash: contentHash, title: title, duration: 0, path: url.path))
        try await engine.load(url)
        // The review as it is now, not as it was before the load: a
        // listener may have answered on one of its threads meanwhile.
        var review = desk.review(of: contentHash) ?? found
        video = OpenVideo(url: url, title: title, contentHash: contentHash)
        draft = nil
        selection = nil
        isDrawingRegion = false
        // They point at threads of the video that was open.
        notices = []
        unread = []
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
    }

    /// The hash of the file at `url`, read off the main actor: it reads the
    /// whole file, and a long video would hold the window still.
    @concurrent
    private nonisolated static func contentHash(of url: URL) async -> String? {
        ContentHash.of(url)
    }

    /// At launch: the video that was open last opens again, paused at its
    /// start, with its history. One whose file is gone, or that doesn't
    /// open any more, leaves the app with no video.
    func openRecent() async {
        guard video == nil, let url = desk.library.recent(), FileManager.default.fileExists(atPath: url.path) else { return }
        do throws(AppRefusal) {
            try await open(url)
        } catch {
            problem = Problem(title: "The last video didn't open", reason: error.reason)
        }
    }

    func play() throws(AppRefusal) {
        try needVideo()
        engine.play()
    }

    func pause() throws(AppRefusal) {
        try needVideo()
        engine.pause()
    }

    func seek(to seconds: Double) async throws(AppRefusal) {
        try needVideo()
        try needInside(seconds)
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
        if let time { await engine.seek(to: time) }
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
        if let draft, Self.hasWords(draft.text) {
            self.draft = nil
            do throws(AppRefusal) {
                _ = try await queueMessage(text: draft.text, time: draft.time, region: draft.region, thread: nil)
            } catch {
                // The words aren't lost: the popover opens again with them.
                if self.draft == nil { self.draft = draft }
                throw error
            }
        }
        let send = try desk.change { review throws(ReviewRefusal) in try review.send(at: Date()) }
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
        // Whoever answers has read the thread.
        unread.remove(id)
        notices.removeAll { $0.thread == id && $0.kind == .question }
        return (report, id.number)
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
            popover: draft.map {
                .init(
                    thread: review?.thread(atFrame: $0.time)?.number ?? review?.nextThreadNumber,
                    time: $0.time, text: $0.text, region: $0.region
                )
            },
            threads: threads.map { StateReport.Thread($0, contentHash: hash, layout: layout) },
            queue: review?.queue.map(\.id.text) ?? [],
            sends: review.map { review in sends.map { StateReport.Send($0, in: review) } } ?? []
        )
        report.transcript = transcript
        report.theme = themes.report
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
        guard !thread.isGeneral, let video else { return nil }
        return layout.keyframe(thread.id, of: video.contentHash)
    }

    /// The PNG of `message`'s region on the open video; nil for a message
    /// on the whole frame.
    func crop(of message: Message) -> URL? {
        guard message.region != nil, let video else { return nil }
        return layout.crop(message.id, of: video.contentHash)
    }

    /// The region to draw on the frame: the one of the message in the
    /// popover, else the latest region of the selected thread while the
    /// player stands on that thread's frame, paused. Once the video moves
    /// on, the frame isn't the one the region was drawn on.
    var shownRegion: ShownRegion? {
        if let draft { return draft.region.map { ShownRegion(region: $0, number: nil) } }
        guard let selection, !engine.isPlaying, let thread = desk.review?.thread(selection), let time = thread.time,
              let region = thread.messages.last(where: { $0.region != nil })?.region,
              abs(engine.time - time) < engine.frameDuration / 2
        else { return nil }
        return ShownRegion(region: region, number: thread.number, state: thread.state)
    }

    // MARK: - What an action needs

    private static let noVideo = AppRefusal("no video is open; open one with `video-review player open <path>`")

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

    /// Space, K, a click on the frame, the play button.
    func togglePlay() {
        guard video != nil else { return }
        if engine.isPlaying { engine.pause() } else { engine.play() }
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

    private func move(to seconds: Double) {
        guard video != nil else { return }
        let target = min(max(seconds, 0), engine.duration)
        Task { await engine.seek(to: target) }
    }

    /// C, Return and the Comment button: pauses and opens the popover at
    /// the frame on screen. With `region`, the rectangle the person drew:
    /// the popover opens on that region, and one that's already open takes
    /// the new region and keeps its words.
    func startDraft(region: Region? = nil) {
        guard video != nil else { return }
        if draft != nil {
            guard let region else { return }
            // The rectangle is on the frame on screen now.
            draft?.region = region
            draft?.time = engine.frameTime(of: engine.time)
            return
        }
        engine.pause()
        draft = Draft(time: engine.frameTime(of: engine.time), text: "", region: region)
    }

    /// Escape in the popover: the message and its region are dropped.
    func cancelDraft() {
        draft = nil
    }

    /// A click on the frame: plays or pauses. While the popover is open it
    /// does nothing: a message is about the frame on screen.
    func clickFrame() {
        if draft == nil { togglePlay() }
    }

    /// The pointer starts to drag on the frame: the video pauses, so the
    /// rectangle is drawn on a still frame.
    func beginRegion() {
        guard video != nil else { return }
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

    /// Escape: drops the rectangle being drawn, else the message in the
    /// popover with its region. False when there was neither.
    @discardableResult
    func escape() -> Bool {
        if isDrawingRegion {
            isDrawingRegion = false
            return true
        }
        guard draft != nil else { return false }
        cancelDraft()
        return true
    }

    /// Return in the popover: queues the draft on the thread of its frame.
    /// A draft with no words stays open.
    func commitDraft() {
        guard let draft, Self.hasWords(draft.text) else { return }
        self.draft = nil
        let before = committing
        commitsUnderWay += 1
        committing = Task {
            defer { commitsUnderWay -= 1 }
            await before?.value
            do throws(AppRefusal) {
                _ = try await queueMessage(text: draft.text, time: draft.time, region: draft.region, thread: nil)
            } catch {
                // The words aren't lost: the popover opens again with them.
                if self.draft == nil { self.draft = draft }
                problem = Problem(title: "The message wasn't queued", reason: error.reason)
            }
        }
    }

    /// Cmd+Return and the Send button: sends the queue, with the words in
    /// the popover. With nothing to send it does nothing.
    func send() {
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

    /// A click on a pin or a thread: selects the thread, pauses and moves
    /// the player to its frame. General has no frame to move to.
    func select(_ id: ThreadID) {
        guard let thread = desk.review?.thread(id) else { return }
        selection = id
        // Its conversation shows: the person sees what the agent said.
        unread.remove(id)
        engine.pause()
        if let time = thread.time { move(to: time) }
    }

    /// Up and Down: the pin before or after the player's time.
    func jumpToMarker(forward: Bool) {
        // Half a frame: the pin the player stands on isn't its own neighbour.
        let slack = engine.frameDuration / 2
        let pinned = frameThreads
        let next = forward
            ? pinned.first { ($0.time ?? 0) > engine.time + slack }
            : pinned.last { ($0.time ?? 0) < engine.time - slack }
        if let next { select(next.id) }
    }

    // MARK: - What the agent says

    /// The agent's name as the threads and the notices show it: the
    /// listener's, or "Agent" before anyone listened.
    var agentName: String { listeners.outbox.session?.name ?? "Agent" }

    /// The agent said something: a notice goes up on the stage, and the
    /// thread it's on is marked until the person looks at it. A notice
    /// that isn't a question goes by itself.
    func raise(_ notice: Notice) {
        notices.append(notice)
        if notice.thread != selection || !isRailVisible { unread.insert(notice.thread) }
        guard let expires = notice.expires else { return }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(expires.timeIntervalSinceNow, 0)))
            self?.dismiss(notice.id)
        }
    }

    /// The notice `id` goes: its time is up.
    func dismiss(_ id: UUID) {
        notices.removeAll { $0.id == id }
    }

    /// A click on a notice: it goes, the rail shows, and the thread it's
    /// on is selected, so its conversation is open with the answer field
    /// under a question.
    func openNotice(_ id: UUID) {
        guard let notice = notices.first(where: { $0.id == id }) else { return }
        dismiss(id)
        isRailVisible = true
        select(notice.thread)
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
