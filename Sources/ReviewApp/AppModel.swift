import AppKit
import Observation
import ReviewCore
import ReviewStore
import ReviewTranscript
import ReviewWire
import UniformTypeIdentifiers

/// The orchestrator: which video is open, the comment being written, the
/// selection, and every action a person or an operator can take. The UI and
/// the control server call the same methods, so a click and its CLI command
/// are one code path.
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

    /// The comment still in the comment box: it has a time, and no id and
    /// no keyframe until it's queued.
    struct Draft: Equatable {
        var time: Double
        var text: String
        /// The rectangle the person drew; nil for the whole frame.
        var region: Region?
    }

    /// A region drawn on the frame, and what it belongs to.
    struct ShownRegion: Equatable {
        var region: Region
        /// The comment's number in time order, as on its marker; nil for
        /// the comment still in the comment box.
        var number: Int?
        /// The comment's state, which its pin is drawn by.
        var state = CommentState.draft
    }

    /// Why the last thing the person asked for didn't work.
    struct Problem: Equatable {
        var title: String
        var reason: String
    }

    let engine = PlayerEngine()
    /// The open video's review, and the one path for changing it.
    let desk: ReviewDesk
    /// The listener's side: the batches in line and whether an agent is
    /// there for them.
    let listeners: ListenerQueue
    /// The transcripts of the videos opened in this run.
    let transcripts: TranscriptDesk
    /// Where this run keeps its data: the person's own, or a demo's.
    let support: URL
    /// Whether this run is on demo data (`app open --demo`).
    let isDemo: Bool
    private(set) var video: OpenVideo?
    /// The comment being written; nil while the comment box is closed.
    var draft: Draft?
    /// The comment whose marker and row are picked out.
    private(set) var selection: ItemID?
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
    /// The comments with an agent message the person hasn't looked at.
    private(set) var unread: Set<ItemID> = []

    @ObservationIgnored private let layout: SupportLayout
    /// The comment the comment box is queueing: its keyframe is being
    /// written. A send waits for it.
    @ObservationIgnored private var committing: Task<Void, Never>?
    /// How many comments from the comment box are on their way into the queue.
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
        listeners.transcripts = transcripts
        listeners.announce = { [weak self] notice in self?.raise(notice) }
    }

    /// The open video's transcript as `state` and the Context popover show
    /// it: its source, and how far it is.
    var transcript: StateReport.Transcript? {
        video.flatMap { transcripts.report(of: $0.contentHash) }
    }

    /// The open video's comments, in time order.
    var comments: [Comment] { desk.review?.comments ?? [] }

    /// The open video's batches, in the order they were sent.
    var batches: [Batch] { desk.review?.batches ?? [] }

    /// Whether Cmd+Return has something to send: a queued comment, one on
    /// its way into the queue, or words in the comment box.
    var canSend: Bool {
        sendCount > 0
    }

    /// How many comments a send would deliver now.
    var sendCount: Int {
        comments.count { $0.state == .queued } + commitsUnderWay + (draft.map { Self.hasWords($0.text) } == true ? 1 : 0)
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
        // listener may have answered one of its comments meanwhile.
        var review = desk.review(of: contentHash) ?? found
        video = OpenVideo(url: url, title: title, contentHash: contentHash)
        draft = nil
        selection = nil
        isDrawingRegion = false
        // They point at comments of the video that was open.
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

    /// Queues a comment at `at`, or where the player is, on `region` of
    /// the frame when it has one. As a person would, it pauses and moves
    /// the player to the comment's time first.
    func addComment(text: String, at: Double?, region: Region? = nil) async throws(AppRefusal) -> StateReport.Comment {
        try needVideo()
        try needWords(text)
        if let at { try needInside(at) }
        engine.pause()
        if let at { await engine.seek(to: at) }
        return try await queueComment(text: text, time: at ?? currentCommentTime, region: region)
    }

    func editComment(_ id: String, text: String) throws(AppRefusal) -> StateReport.Comment {
        let id = try commentID(id)
        return report(try desk.change { review throws(ReviewRefusal) in try review.editComment(id, text: text) })
    }

    func deleteComment(_ id: String) throws(AppRefusal) -> StateReport.Comment {
        let id = try commentID(id)
        let comment = try desk.change { review throws(ReviewRefusal) in try review.deleteComment(id) }
        let report = report(comment)
        ImageFiles.remove(URL(fileURLWithPath: report.keyframePath))
        if let crop = report.cropPath { ImageFiles.remove(URL(fileURLWithPath: crop)) }
        if selection == id { selection = nil }
        return report
    }

    /// The context popover's Save and `context set`: the open video's
    /// context note, kept without the space around it. The listener gets
    /// it under the sidecar's text with the next batch. An empty text
    /// clears the note.
    @discardableResult
    func setContextNote(_ text: String) throws(AppRefusal) -> String {
        let note = text.trimmingCharacters(in: .whitespacesAndNewlines)
        try desk.change { review in review.note = note }
        return note
    }

    /// Cmd+Return and `batch send`: every queued comment of the open video
    /// goes out as one batch, which the listener's `wait` gets, now or when
    /// it next opens. Words still in the comment box are queued first, so
    /// nothing is left behind. Refused when nothing is queued.
    func sendBatch() async throws(AppRefusal) -> StateReport.Batch {
        try needVideo()
        // A comment whose keyframe is still being written joins the batch.
        await committing?.value
        if let draft, Self.hasWords(draft.text) {
            self.draft = nil
            do throws(AppRefusal) {
                _ = try await queueComment(text: draft.text, time: draft.time, region: draft.region)
            } catch {
                // The words aren't lost: the box opens again with them.
                if self.draft == nil { self.draft = draft }
                throw error
            }
        }
        let batch = try desk.change { review throws(ReviewRefusal) in
            try review.send(batchID: ItemID.make(.batch), at: Date())
        }
        if let video { listeners.enqueue(BatchRef(batchID: batch.id, contentHash: video.contentHash)) }
        return report(batch)
    }

    /// The answer box and `thread answer`: the person's answer to the open
    /// question of a comment. The `ask` that waits for it exits with it.
    func answer(_ commentID: String, text: String) throws(AppRefusal) -> StateReport.Comment {
        let id = try self.commentID(commentID)
        guard let hash = desk.contentHash(of: id) else { throw AppRefusal(ReviewRefusal.unknownComment(commentID).line) }
        let message = try desk.change(hash) { review throws(ReviewRefusal) in
            try review.answer(id, text: text, messageID: ItemID.make(.message), at: Date())
        }
        listeners.answered(id, with: message)
        // Whoever answers has read the thread.
        unread.remove(id)
        notices.removeAll { $0.subject == .comment(id) && $0.kind == .question }
        guard let comment = desk.review(of: hash)?.comment(id) else { throw AppRefusal(ReviewRefusal.unknownComment(commentID).line) }
        return StateReport.Comment(comment, contentHash: hash, layout: layout)
    }

    func state() -> StateReport {
        var report = StateReport(
            app: .init(version: Version.app, demo: isDemo, support: support.path),
            video: video.map {
                .init(
                    path: $0.url.path, contentHash: $0.contentHash, title: $0.title, duration: engine.duration,
                    contextNote: contextNote
                )
            },
            player: .init(time: engine.time, playing: engine.isPlaying),
            draft: draft.map { .init(time: $0.time, text: $0.text, region: $0.region) },
            comments: comments.map(report),
            batches: batches.map(report)
        )
        report.transcript = transcript
        return report
    }

    private func report(_ batch: Batch) -> StateReport.Batch {
        StateReport.Batch(batch)
    }

    // MARK: - Comments

    /// The time a comment made now gets: the player's, raised to the next
    /// millisecond.
    private var currentCommentTime: Double {
        Self.commentTime(player: engine.time, duration: engine.duration)
    }

    /// The player's time as a comment keeps it: to the millisecond, and
    /// never before the frame on screen. A frame rarely starts on a whole
    /// millisecond (7.2333… s at 30 frames a second); rounding down would
    /// name the frame before it.
    static func commentTime(player: Double, duration: Double) -> Double {
        // The player's own noise, far below a millisecond, isn't raised.
        let milliseconds = (max(player, 0) * 1000 - 1e-6).rounded(.up)
        return min(milliseconds / 1000, duration)
    }

    /// Writes the keyframe and the region's crop, then queues the comment
    /// and selects it. A comment never exists without its pictures.
    private func queueComment(text: String, time: Double, region: Region?) async throws(AppRefusal) -> StateReport.Comment {
        guard let video, let asset = engine.asset else { throw Self.noVideo }
        try needWords(text)
        let id = ItemID.make(.comment)
        let file = layout.keyframe(id, of: video.contentHash)
        let cropFile = layout.crop(id, of: video.contentHash)
        try await FrameGrabber.writeImages(
            of: asset, at: time, duration: engine.duration, frameDuration: engine.frameDuration,
            keyframe: file, region: region, crop: cropFile
        )
        do throws(AppRefusal) {
            guard self.video == video else { throw AppRefusal("another video opened before the comment was queued") }
            let comment = try desk.change { review throws(ReviewRefusal) in
                try review.addComment(id: id, time: time, text: text, region: region)
            }
            selection = id
            return report(comment)
        } catch {
            ImageFiles.remove(file)
            ImageFiles.remove(cropFile)
            throw error
        }
    }

    private func report(_ comment: Comment) -> StateReport.Comment {
        StateReport.Comment(comment, contentHash: video?.contentHash ?? "", layout: layout)
    }

    /// The keyframe PNG of `comment` on the open video.
    func keyframe(of comment: Comment) -> URL? {
        video.map { layout.keyframe(comment.id, of: $0.contentHash) }
    }

    /// The PNG of `comment`'s region on the open video; nil for a comment
    /// on the whole frame.
    func crop(of comment: Comment) -> URL? {
        guard comment.region != nil, let video else { return nil }
        return layout.crop(comment.id, of: video.contentHash)
    }

    /// The region to draw on the frame: the one of the comment in the
    /// comment box, else the selected comment's while the player stands on
    /// that comment's frame, paused. Once the video moves on, the frame
    /// isn't the one the region was drawn on.
    var shownRegion: ShownRegion? {
        if let draft { return draft.region.map { ShownRegion(region: $0, number: nil) } }
        guard let selection, !engine.isPlaying,
              let index = comments.firstIndex(where: { $0.id == selection }), let region = comments[index].region,
              abs(engine.time - comments[index].time) < engine.frameDuration / 2
        else { return nil }
        return ShownRegion(region: region, number: index + 1, state: comments[index].state)
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

    private func commentID(_ text: String) throws(AppRefusal) -> ItemID {
        guard let id = ItemID(text), id.kind == .comment else {
            throw AppRefusal(ReviewRefusal.unknownComment(text).line)
        }
        return id
    }

    // MARK: - The person's gestures

    /// Space, K, a click on the frame, the play button.
    func togglePlay() {
        guard video != nil else { return }
        if engine.isPlaying { engine.pause() } else { engine.play() }
    }

    /// Left and Right: `seconds` back or forward, kept inside the video.
    func skip(by seconds: Double) {
        move(to: engine.time + seconds)
    }

    /// Shift+Left and Shift+Right: `frames` back or forward.
    func step(frames: Int) {
        engine.pause()
        move(to: engine.time + Double(frames) * engine.frameDuration)
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

    /// C, Return and the Comment button: pauses and opens the comment box
    /// at the player's time. With `region`, the rectangle the person drew:
    /// the box opens on that region, and a box that's already open takes
    /// the new region and keeps its words.
    func startDraft(region: Region? = nil) {
        guard video != nil else { return }
        if draft != nil {
            guard let region else { return }
            // The rectangle is on the frame on screen now.
            draft?.region = region
            draft?.time = currentCommentTime
            return
        }
        engine.pause()
        draft = Draft(time: currentCommentTime, text: "", region: region)
    }

    /// Escape in the comment box: the comment and its region are dropped.
    func cancelDraft() {
        draft = nil
    }

    /// A click on the frame: plays or pauses. While the comment box is
    /// open it does nothing: a comment is about the frame on screen.
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

    /// The pointer lets go: the comment box opens on `region`. A drag
    /// that Escape cancelled, or one too small to be a region (nil), opens
    /// nothing.
    func endRegion(_ region: Region?) {
        guard isDrawingRegion else { return }
        isDrawingRegion = false
        if let region { startDraft(region: region) }
    }

    /// Escape: drops the rectangle being drawn, else the comment in the
    /// comment box with its region. False when there was neither.
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

    /// Return in the comment box: queues the draft. A draft with no words
    /// stays open.
    func commitDraft() {
        guard let draft, Self.hasWords(draft.text) else { return }
        self.draft = nil
        let before = committing
        commitsUnderWay += 1
        committing = Task {
            defer { commitsUnderWay -= 1 }
            await before?.value
            do throws(AppRefusal) {
                _ = try await queueComment(text: draft.text, time: draft.time, region: draft.region)
            } catch {
                // The words aren't lost: the box opens again with them.
                if self.draft == nil { self.draft = draft }
                problem = Problem(title: "The comment wasn't queued", reason: error.reason)
            }
        }
    }

    /// Cmd+Return and the Send button: sends the queue, with the words in
    /// the comment box. With nothing to send it does nothing.
    func send() {
        // A second press while the first is on its way has nothing to add.
        guard canSend, !isSending else { return }
        isSending = true
        Task {
            defer { isSending = false }
            do throws(AppRefusal) {
                _ = try await sendBatch()
            } catch {
                problem = Problem(title: "The comments weren't sent", reason: error.reason)
            }
        }
    }

    /// A click on a marker or a row: selects the comment, pauses and
    /// moves the player to its time.
    func select(_ id: ItemID) {
        guard let comment = desk.review?.comment(id) else { return }
        selection = id
        // Its thread opens with the row: the person sees what the agent said.
        unread.remove(id)
        engine.pause()
        move(to: comment.time)
    }

    /// Up and Down: the marker before or after the player's time.
    func jumpToMarker(forward: Bool) {
        // Half a frame: the marker the player stands on isn't its own neighbour.
        let slack = engine.frameDuration / 2
        let next = forward
            ? comments.first { $0.time > engine.time + slack }
            : comments.last { $0.time < engine.time - slack }
        if let next { select(next.id) }
    }

    // MARK: - What the agent says

    /// The agent's name as the threads and the notices show it: the
    /// listener's, or "Agent" before anyone listened.
    var agentName: String { listeners.outbox.session?.name ?? "Agent" }

    /// The agent said something: a notice goes up on the stage, and the
    /// comment it's about is marked until the person looks at it. A notice
    /// that isn't a question goes by itself.
    func raise(_ notice: Notice) {
        notices.append(notice)
        if case .comment(let id) = notice.subject, id != selection || !isRailVisible { unread.insert(id) }
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

    /// A click on a notice: it goes, the rail shows, and the comment it's
    /// about is selected, so its thread is open with the answer box under
    /// a question.
    func openNotice(_ id: UUID) {
        guard let notice = notices.first(where: { $0.id == id }) else { return }
        dismiss(id)
        isRailVisible = true
        if case .comment(let comment) = notice.subject { select(comment) }
    }

    /// Return in an answer box and its button: the person's answer to the
    /// comment's open question. False when it wasn't taken.
    @discardableResult
    func answerQuestion(_ id: ItemID, text: String) -> Bool {
        do throws(AppRefusal) {
            _ = try answer(id.text, text: text)
            return true
        } catch {
            problem = Problem(title: "The answer wasn't sent", reason: error.reason)
            return false
        }
    }

    /// Save on a row: the comment's new text.
    func edit(_ id: ItemID, text: String) {
        do throws(AppRefusal) {
            _ = try editComment(id.text, text: text)
        } catch {
            problem = Problem(title: "The comment didn't change", reason: error.reason)
        }
    }

    /// Delete on a row.
    func delete(_ id: ItemID) {
        do throws(AppRefusal) {
            _ = try deleteComment(id.text)
        } catch {
            problem = Problem(title: "The comment wasn't deleted", reason: error.reason)
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

    /// Whether the listener's next batch of the open video carries the
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
