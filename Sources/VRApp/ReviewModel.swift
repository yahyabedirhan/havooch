import Foundation
import Observation
import VRReview
import VRStore
import VRTranscript

/// Why the model won't do what was asked, as one line.
struct ModelRefusal: Error, Equatable {
    var reason: String

    init(_ reason: String) {
        self.reason = reason
    }
}

/// The orchestrator the views and the control desks call. A person and an
/// operator agent reach the same methods here, so nothing the window can do
/// skips the model, and every action has a command.
@MainActor
@Observable
final class ReviewModel {
    /// The open video, or nil before one is opened.
    private(set) var video: VideoFile?
    /// The demo folder in a demo run (`app open --demo`), else nil.
    let demoFolder: URL?
    /// Why the last open a person asked for didn't work, for the window to
    /// show; nil once it's been read.
    var openFailure: String?
    /// The open video's review, or nil before a video is opened.
    private(set) var session: ReviewSession?
    /// The comment whose card is selected, or nil.
    private(set) var selection: String?
    /// The draft the comment box is open on, or nil when it's closed.
    private(set) var composing: String?
    /// The comments whose keyframe is on disk.
    private(set) var keyframes: Set<String> = []
    /// The comments whose region's crop is on disk.
    private(set) var crops: Set<String> = []
    /// What the comment box holds, so that sending from inside the box
    /// queues it first.
    var composerText = ""
    /// The batches sent and not finished, and the listener they go to. Its
    /// parcels are kept on disk on every change (`deliver`); the listener
    /// lives for the run.
    private(set) var outbox = Outbox()
    /// Why the last send a person asked for didn't work, for the send bar;
    /// nil after one that did.
    private(set) var sendFailure: String?
    /// The agent's messages the stage shows a brief notice of, oldest first.
    /// Each goes by itself after `noticeLifetime`.
    private(set) var notices: [Notice] = []

    /// Told when a batch was posted to the outbox: the listener desk gives
    /// it to a `wait` that is open.
    @ObservationIgnored var posted: (@MainActor () -> Void)?
    /// Told when the question on a comment was answered: the listener desk
    /// gives the answer to an `ask` that is open on it.
    @ObservationIgnored var answered: (@MainActor (String) -> Void)?
    /// How long a notice stays.
    @ObservationIgnored var noticeLifetime = Notice.lifetime
    @ObservationIgnored private let player: any Playing
    @ObservationIgnored private let frames: any FrameGrabbing
    @ObservationIgnored private let library: Library
    /// What the videos opened in this run say.
    let transcripts: TranscriptService
    @ObservationIgnored private let now: @MainActor () -> Date
    /// Whether a send a person asked for is on its way.
    @ObservationIgnored private var isSending = false
    /// Each comment's keyframe, and its region's crop, being written: nil
    /// once they're on disk, or why they couldn't be saved.
    @ObservationIgnored private var grabs: [String: Task<String?, Never>] = [:]
    /// Reads the transcripts of the videos whose batches the last run left
    /// in the outbox; nil when it left none, and once they're read.
    @ObservationIgnored private var restoring: Task<Void, Never>?

    init(
        player: any Playing,
        frames: any FrameGrabbing,
        library: Library,
        speech: any Transcriber = SpeechSource(),
        demoFolder: URL? = nil,
        now: @escaping @MainActor () -> Date = { Date() }
    ) {
        self.player = player
        self.frames = frames
        self.library = library
        transcripts = TranscriptService(speech: speech, cache: TranscriptCache(root: library.root))
        self.demoFolder = demoFolder
        self.now = now
        restoreOutbox()
    }

    var time: Double { player.time }
    var isPlaying: Bool { player.isPlaying }
    /// The open video's length in seconds; 0 with none.
    var duration: Double { video?.info.duration ?? 0 }
    /// The open video's comments that were written, in time order: what the
    /// timeline marks and the sidebar lists. A draft isn't among them.
    var comments: [Comment] { session?.comments.filter { $0.state != .draft } ?? [] }

    /// The open video's note; empty with none, or with no video.
    var note: String { session?.note ?? "" }

    /// The open video's context sidecar as it is on disk now, or nil with
    /// none, or with no video.
    var sidecar: ContextSidecar? {
        video.flatMap { ContextSidecar.find(beside: $0.url) }
    }

    /// Where the keyframe of the comment `id` is, or nil while it isn't on
    /// disk.
    func keyframeURL(for id: String) -> URL? {
        guard keyframes.contains(id), let session else { return nil }
        return library.keyframeURL(session.video.contentHash, comment: id)
    }

    /// Where the crop of the region of the comment `id` is, or nil when it
    /// has no region or the crop isn't on disk yet.
    func cropURL(for id: String) -> URL? {
        guard crops.contains(id), let session else { return nil }
        return library.cropURL(session.video.contentHash, comment: id)
    }

    /// The rectangles the stage draws over the frame now.
    var marks: [RegionMark] {
        RegionMark.shown(of: session?.comments ?? [], selection: selection, composing: composing, time: time)
    }

    // MARK: - What a person and an operator can do

    /// Opens the video at `url`, paused at its start. A file the player
    /// can't play is refused with the reason, and the open video stays.
    func open(_ url: URL) async throws(ModelRefusal) {
        let file = try await VideoFile.read(url)
        let hash = file.info.contentHash
        // The history is by the file's content: a renamed copy has it too.
        let stored: ReviewSession?
        do {
            stored = try library.session(for: hash)
        } catch {
            throw ModelRefusal("couldn't read the review kept for \(url.path): \(error.localizedDescription)")
        }
        do {
            try await player.load(url)
        } catch {
            throw ModelRefusal("couldn't open \(url.path): \(error.localizedDescription)")
        }
        cancelComposer()
        // The open video opened again keeps what this run holds of it.
        let open = session?.video.contentHash == hash ? session : nil
        var opened = open ?? stored ?? ReviewSession(video: file.info)
        if opened.video != file.info {
            // The file may have moved since: the review keeps the last path seen.
            opened.video = file.info
            if stored != nil { try? library.save(opened) }
        }
        // What a draft left when the app quit with its comment box open.
        library.removeImages(of: hash, keeping: Set(opened.comments.map(\.id)))
        findImages(of: opened)
        session = opened
        selection = nil
        video = file
        // A sidecar's lines are known when this returns; speech goes on in
        // the background.
        await transcripts.start(file)
    }

    /// Plays from where the player is; from the start when it's at the end.
    func play() async throws(ModelRefusal) {
        let video = try openVideo()
        if player.time >= video.info.duration - Self.endMargin {
            await player.seek(to: 0)
        }
        player.play()
    }

    func pause() throws(ModelRefusal) {
        _ = try openVideo()
        player.pause()
    }

    /// Moves the player to `seconds`, exactly. A time outside the video is
    /// refused.
    func seek(to seconds: Double) async throws(ModelRefusal) {
        try inside(seconds, of: try openVideo())
        await player.seek(to: seconds)
    }

    /// Starts a comment at `seconds`, or at the player's time, on `region`
    /// of the frame when one is given: a draft with its time, whose keyframe
    /// starts being written from the video file, and its region's crop cut
    /// from that keyframe. Returns the draft's id, for `commitComment` or
    /// `discardComment`.
    func beginComment(at seconds: Double? = nil, region: Region? = nil) throws(ModelRefusal) -> String {
        let video = try openVideo()
        if let seconds { try inside(seconds, of: video) }
        let time = TimeText.rounded(min(max(0, seconds ?? player.time), video.info.duration))
        let id: String
        do {
            id = try library.nextCommentID()
        } catch {
            throw ModelRefusal("couldn't number the comment: \(error.localizedDescription)")
        }
        session?.draft(id: id, time: time, region: region)
        grabs[id] = grab(id, at: time, region: region, of: video)
        return id
    }

    /// Writes the keyframe of the comment `id` from the video file, then
    /// cuts its region's crop from it. The task ends with nil once they're
    /// on disk, or with why they couldn't be saved.
    private func grab(_ id: String, at time: Double, region: Region?, of video: VideoFile) -> Task<String?, Never> {
        let hash = video.info.contentHash
        let file = library.keyframeURL(hash, comment: id)
        let crop = library.cropURL(hash, comment: id)
        return Task { [frames, weak self] in
            var failure: String?
            do {
                _ = try await frames.writeKeyframe(of: video.url, at: time, to: file)
                if let region { try await frames.writeCrop(of: file, region: region, to: crop) }
            } catch {
                failure = error.localizedDescription
            }
            // The comment may have been dropped while its images were written.
            let kept = self?.review(of: hash)?.comment(id) != nil
            for (image, isCrop) in [(file, false), (crop, true)] where FileManager.default.fileExists(atPath: image.path) {
                if kept, let self {
                    if isCrop { self.crops.insert(id) } else { self.keyframes.insert(id) }
                } else {
                    try? FileManager.default.removeItem(at: image)
                }
            }
            return failure
        }
    }

    /// Gives the draft `id` its text and queues it.
    func commitComment(_ id: String, text: String) throws(ModelRefusal) {
        try change { (session) throws(ReviewRefusal) in try session.commit(id, text: text) }
        if composing == id { composing = nil }
        selection = id
        // There's something to send again: an earlier refusal is stale.
        sendFailure = nil
    }

    /// Drops the draft `id`, its keyframe and its crop.
    func discardComment(_ id: String) throws(ModelRefusal) {
        try change { (session) throws(ReviewRefusal) in try session.discard(id) }
        if composing == id { composing = nil }
        dropImages(of: id)
    }

    /// Queues a comment in one step, as the command line does: the video is
    /// paused, and moved to `seconds` first when it's given, so the window
    /// shows what was commented on. Returns once the keyframe, and the crop
    /// of `region` when one is given, are on disk; a frame or a crop that
    /// can't be saved refuses the comment.
    func addComment(text: String, at seconds: Double? = nil, region: Region? = nil) async throws(ModelRefusal) -> Comment {
        let video = try openVideo()
        do throws(ReviewRefusal) {
            _ = try ReviewSession.written(text)
        } catch {
            throw ModelRefusal(error.reason)
        }
        if let seconds {
            try inside(seconds, of: video)
            await player.seek(to: seconds)
        }
        player.pause()
        let id = try beginComment(at: seconds, region: region)
        if let failure = await grabs[id]?.value {
            let time = session?.comment(id)?.time ?? 0
            try? discardComment(id)
            throw ModelRefusal("couldn't save the frame at \(TimeText.exact(time)): \(failure)")
        }
        try commitComment(id, text: text)
        guard let comment = session?.comment(id) else { throw ModelRefusal("the comment \(id) didn't queue") }
        return comment
    }

    /// Replaces a queued comment's text.
    func editComment(_ id: String, text: String) throws(ModelRefusal) {
        try change { (session) throws(ReviewRefusal) in try session.edit(id, text: text) }
    }

    /// Takes a queued comment out, with its keyframe and its crop.
    func deleteComment(_ id: String) throws(ModelRefusal) {
        try change { (session) throws(ReviewRefusal) in try session.delete(id) }
        if selection == id { selection = nil }
        dropImages(of: id)
    }

    /// Replaces the open video's note, the part of its context the person
    /// writes in the app. An empty text takes it away. The listener gets
    /// the changed context with the next batch.
    func setNote(_ text: String) throws(ModelRefusal) {
        try change { (session) throws(ReviewRefusal) in session.setNote(text) }
    }

    /// Shows a comment's moment: the video paused at its time and its card
    /// selected. What a click on its marker or its card does.
    func showComment(_ id: String) async throws(ModelRefusal) {
        _ = try openVideo()
        guard let comment = session?.comment(id), comment.state != .draft else {
            throw ModelRefusal("there's no comment \(id)")
        }
        player.pause()
        await player.seek(to: comment.time)
        selection = id
    }

    /// Sends every queued comment of the open video as one batch, for a
    /// listener's `wait`: what Cmd+Enter and `batch send` both do. With no
    /// listener, the batch waits in the outbox for the next one. A queued
    /// comment whose keyframe or crop isn't on disk has it grabbed once
    /// more, and is sent with what it has: a frame that can't be saved never
    /// holds the batch back.
    func sendBatch() async throws(ModelRefusal) -> Batch {
        let video = try openVideo()
        let hash = video.info.contentHash
        var checked: Set<String> = []
        // A comment queued while the frames of the others are waited for goes too.
        while let comment = session?.queue.first(where: { !checked.contains($0.id) }) {
            checked.insert(comment.id)
            _ = await grabs[comment.id]?.value
            let hasImages = keyframes.contains(comment.id) && (comment.region == nil || crops.contains(comment.id))
            if !hasImages, review(of: hash)?.comment(comment.id) != nil {
                let again = grab(comment.id, at: comment.time, region: comment.region, of: video)
                grabs[comment.id] = again
                _ = await again.value
            }
        }
        guard self.video?.info.contentHash == hash else {
            throw ModelRefusal("another video was opened while the batch was sent; nothing was sent")
        }
        guard session?.queue.isEmpty == false else {
            throw ModelRefusal("there's nothing to send: no comment is queued")
        }
        let id: String
        do {
            id = try library.nextBatchID()
        } catch {
            throw ModelRefusal("couldn't number the batch: \(error.localizedDescription)")
        }
        // The parcel is kept before the review says the batch was sent: a
        // crash between the two leaves a parcel of no batch, which the next
        // launch drops, and never a sent batch no listener gets.
        var posting = outbox
        posting.post(batchID: id, videoHash: hash)
        do {
            try library.save(posting)
        } catch {
            throw ModelRefusal("couldn't keep the batch: \(error.localizedDescription)")
        }
        outbox = posting
        var sent: Batch?
        do throws(ModelRefusal) {
            try change { (session) throws(ReviewRefusal) in sent = try session.send(batchID: id, at: now()) }
        } catch {
            deliver { $0.finish(id) }
            throw error
        }
        guard let sent else { throw ModelRefusal("the batch \(id) wasn't sent") }
        sendFailure = nil
        posted?()
        return sent
    }

    /// Answers the question open on the comment `commentID`: what the
    /// answer box in its card and `thread answer` both do. An `ask` waiting
    /// on the comment gets the text.
    func answer(_ commentID: String, text: String) throws(ModelRefusal) {
        try changeReview(of: try hash(ofComment: commentID)) { (review) throws(ReviewRefusal) in
            try review.answer(commentID, text: text, at: now())
        }
        answered?(commentID)
    }

    // MARK: - What the listener can do

    /// Whether a listener is there now, and whether it has work.
    var presence: Outbox.Presence { outbox.presence(at: now()) }

    /// A `wait` opened, from the listener session `key`. From another
    /// session than the last one, the batches that one took and didn't
    /// finish are pending again and their comments back to `sent`.
    func listenerArrived(key: String, name: String) {
        for parcel in deliver({ $0.arrive(key: key, name: name, at: now()) }) {
            try? changeReview(of: parcel.videoHash) { (review) throws(ReviewRefusal) in review.requeue(parcel.batchID) }
        }
    }

    /// The oldest batch waiting for the listener, now taken by it.
    func takeParcel() -> Outbox.Parcel? {
        deliver { $0.take(at: now()) }
    }

    /// A taken batch's payload didn't reach its `wait`: it's pending again.
    func parcelUndelivered(_ batchID: String) {
        deliver { $0.undelivered(batchID) }
    }

    /// A batch nothing can be delivered of leaves the outbox.
    func parcelDropped(_ batchID: String) {
        deliver { $0.finish(batchID) }
    }

    /// A `wait` of the session `key` closed.
    func listenerLeft(key: String, delivered: Bool) {
        outbox.leave(key: key, at: now(), delivered: delivered)
    }

    /// What `wait` prints for `parcel`: the batch's comments that aren't
    /// done or failed, with the paths of their images. The video needn't be
    /// the open one.
    func payload(for parcel: Outbox.Parcel) throws(ModelRefusal) -> BatchPayload {
        guard let review = review(of: parcel.videoHash), let batch = review.batch(parcel.batchID) else {
            throw ModelRefusal("there's no batch \(parcel.batchID)")
        }
        let hash = parcel.videoHash
        findImages(of: review)
        return BatchPayload(
            batch: batch,
            session: review,
            context: outbox.context(for: hash, text: contextText(of: hash)),
            keyframePath: { self.keyframes.contains($0.id) ? self.library.keyframeURL(hash, comment: $0.id).path : nil },
            cropPath: { self.crops.contains($0.id) ? self.library.cropURL(hash, comment: $0.id).path : nil },
            transcript: { self.transcript(around: $0, of: review.video) }
        )
    }

    // The listener answers by a comment's or a batch's id alone. Its video
    // needn't be the open one, nor one opened in this run: the library's
    // index says which video an id belongs to (`hash(ofComment:)`).

    /// `ack`: each comment of the batch still `sent` is `acknowledged`, and
    /// `text`, when given, is a message for the full batch.
    func acknowledge(_ batchID: String, text: String?) throws(ModelRefusal) {
        let hash = try hash(ofBatch: batchID)
        try changeReview(of: hash) { (review) throws(ReviewRefusal) in
            try review.acknowledge(batchID, text: text, at: now())
        }
        if text != nil, let message = review(of: hash)?.batch(batchID)?.thread.last {
            notify(message, on: nil, batch: batchID)
        }
    }

    /// `status`: the comment is `working`, `done` or `failed`. A batch whose
    /// comments are all done or failed is finished and leaves the outbox,
    /// so the listener has no work of it left.
    func setStatus(_ commentID: String, to state: CommentState) throws(ModelRefusal) {
        let hash = try hash(ofComment: commentID)
        try changeReview(of: hash) { (review) throws(ReviewRefusal) in try review.setStatus(commentID, to: state) }
        if let review = review(of: hash), let batch = review.comment(commentID)?.batchID, review.isFinished(batch) {
            deliver { $0.finish(batch) }
        }
    }

    /// `reply`: the agent's message in the thread of the comment or the
    /// batch `id`, with a notice. Returns where it went.
    @discardableResult
    func reply(to id: String, text: String) throws(ModelRefusal) -> ReviewSession.Place {
        guard let hash = (try? hash(ofBatch: id)) ?? (try? hash(ofComment: id)) else {
            throw ModelRefusal("there's no comment or batch \(id)")
        }
        let place = try changeReview(of: hash) { (review) throws(ReviewRefusal) in try review.reply(to: id, text: text, at: now()) }
        switch place {
        case .batch:
            if let message = review(of: hash)?.batch(id)?.thread.last { notify(message, on: nil, batch: id) }
        case .comment:
            if let comment = review(of: hash)?.comment(id), let message = comment.thread.last {
                notify(message, on: comment, batch: comment.batchID ?? "")
            }
        }
        return place
    }

    /// `ask`: the agent's question in the comment's thread, with a notice.
    /// The question that is already open, asked again, adds nothing.
    func ask(_ commentID: String, question: String) throws(ModelRefusal) {
        let hash = try hash(ofComment: commentID)
        let before = review(of: hash)?.comment(commentID)?.thread.count
        try changeReview(of: hash) { (review) throws(ReviewRefusal) in try review.ask(commentID, question: question, at: now()) }
        if let comment = review(of: hash)?.comment(commentID), comment.thread.count != before, let message = comment.thread.last {
            notify(message, on: comment, batch: comment.batchID ?? "")
        }
    }

    /// The last answer on the comment with its question, when no `ask` has
    /// been given it yet.
    func unheardAnswer(on commentID: String) -> ReviewSession.Exchange? {
        guard let hash = try? hash(ofComment: commentID) else { return nil }
        return review(of: hash)?.unheardAnswer(on: commentID)
    }

    /// The answer on the comment reached an `ask`: it isn't given again.
    func answerHeard(_ commentID: String) {
        guard let hash = try? hash(ofComment: commentID) else { return }
        try? changeReview(of: hash) { (review) throws(ReviewRefusal) in review.answerHeard(commentID) }
    }

    /// Shows a notice of the agent's `message`, gone by itself after
    /// `noticeLifetime`.
    private func notify(_ message: ThreadMessage, on comment: Comment?, batch: String) {
        let notice = Notice(id: UUID(), commentID: comment?.id, time: comment?.time, batchID: batch, message: message)
        notices.append(notice)
        Task { [weak self, noticeLifetime] in
            try? await Task.sleep(for: noticeLifetime)
            self?.dismissNotice(notice.id)
        }
    }

    /// Takes a notice away, before its time or at it.
    func dismissNotice(_ id: UUID) {
        notices.removeAll { $0.id == id }
    }

    /// The context of the video `hash` as a listener gets it: its sidecar's
    /// text and the person's note, or nil with neither. The sidecar is read
    /// from disk on every call, so an edit to it reaches the next batch; the
    /// outbox sends the text once per listener session and when it changed.
    private func contextText(of hash: String) -> String? {
        guard let review = review(of: hash) else { return nil }
        let sidecar = ContextSidecar.find(beside: URL(fileURLWithPath: review.video.path))
        return ContextSidecar.text(sidecar: sidecar?.text, note: review.note)
    }

    /// The transcript lines from 15 s before a comment's time to 15 s after,
    /// as they're known now: none while speech is still being recognized.
    private func transcript(around comment: Comment, of video: VideoInfo) -> [BatchPayload.Line] {
        transcripts.lines(of: video.contentHash, around: comment.time, duration: video.duration)
            .map { BatchPayload.Line(start: $0.start, end: $0.end, text: $0.text) }
    }

    /// How close to the end counts as at the end, in seconds.
    private static let endMargin = 0.05

    private func openVideo() throws(ModelRefusal) -> VideoFile {
        guard let video else {
            throw ModelRefusal("no video is open; `video-review player open <path>`")
        }
        return video
    }

    /// Refuses a time outside `video`.
    private func inside(_ seconds: Double, of video: VideoFile) throws(ModelRefusal) {
        guard (0...video.info.duration).contains(seconds) else {
            throw ModelRefusal(
                "\(TimeText.exact(seconds)) is outside the video (\(TimeText.exact(0)) to \(TimeText.exact(video.info.duration)))"
            )
        }
    }

    /// Changes the open video's review; the review's refusal is the model's.
    private func change(_ body: (inout ReviewSession) throws(ReviewRefusal) -> Void) throws(ModelRefusal) {
        try changeReview(of: try openVideo().info.contentHash, body)
    }

    /// The review of the video `hash`: the open one, or the one the library
    /// keeps.
    private func review(of hash: String) -> ReviewSession? {
        if let session, session.video.contentHash == hash { return session }
        return (try? library.session(for: hash)) ?? nil
    }

    /// Changes the review of the video `hash`, open or not, and keeps it on
    /// disk before the change shows. The review's refusal is the model's,
    /// and so is a review that can't be saved; both leave it as it was.
    @discardableResult
    private func changeReview<Value>(
        of hash: String, _ body: (inout ReviewSession) throws(ReviewRefusal) -> Value
    ) throws(ModelRefusal) -> Value {
        guard let review = review(of: hash) else { throw ModelRefusal("there's no review of that video") }
        var changed = review
        let value: Value
        do throws(ReviewRefusal) {
            value = try body(&changed)
        } catch {
            throw ModelRefusal(error.reason)
        }
        // A draft isn't kept, so a change to one writes nothing.
        if changed.kept != review.kept {
            do {
                try library.save(changed)
            } catch {
                throw ModelRefusal("couldn't save the review of \(review.video.title): \(error.localizedDescription)")
            }
        }
        if session?.video.contentHash == hash { session = changed }
        return value
    }

    /// The video whose review has the comment `id`: the open one, or the
    /// one the library's index names.
    private func hash(ofComment id: String) throws(ModelRefusal) -> String {
        if let session, session.comment(id) != nil { return session.video.contentHash }
        guard let hash = library.videoHash(forComment: id), review(of: hash)?.comment(id) != nil else {
            throw ModelRefusal("there's no comment \(id)")
        }
        return hash
    }

    /// The video whose review has the batch `id`.
    private func hash(ofBatch id: String) throws(ModelRefusal) -> String {
        if let session, session.batch(id) != nil { return session.video.contentHash }
        guard let hash = library.videoHash(forBatch: id), review(of: hash)?.batch(id) != nil else {
            throw ModelRefusal("there's no batch \(id)")
        }
        return hash
    }

    /// Changes the outbox, and keeps its parcels on disk when they changed.
    /// A change that can't be kept still holds for this run.
    @discardableResult
    private func deliver<Value>(_ body: (inout Outbox) -> Value) -> Value {
        let before = outbox.parcels
        let value = body(&outbox)
        if outbox.parcels != before {
            do {
                try library.save(outbox)
            } catch {
                Self.complain("couldn't keep the outbox: \(error.localizedDescription)")
            }
        }
        return value
    }

    /// Takes up the outbox the last run kept. The `wait` that took a batch
    /// ended with that run, so a batch taken and not finished is pending
    /// again and its unfinished comments are back to `sent`. A parcel whose
    /// batch is finished, or isn't in its review, is what a crash between
    /// two writes left: it's dropped.
    private func restoreOutbox() {
        do {
            outbox = try library.outbox()
        } catch {
            Self.complain("couldn't read the outbox: \(error.localizedDescription)")
            return
        }
        guard !outbox.parcels.isEmpty else { return }
        deliver { outbox in
            for parcel in outbox.restart() {
                try? changeReview(of: parcel.videoHash) { (review) throws(ReviewRefusal) in review.requeue(parcel.batchID) }
            }
            for parcel in outbox.parcels {
                // A review that can't be read keeps its parcel.
                let kept: ReviewSession?
                do { kept = try library.session(for: parcel.videoHash) } catch { continue }
                if kept?.batch(parcel.batchID) == nil || kept?.isFinished(parcel.batchID) == true {
                    outbox.finish(parcel.batchID)
                }
            }
        }
        // A batch may go to a `wait` before its video is opened in this
        // run: what the video says is read now.
        let waiting = Set(outbox.parcels.map(\.videoHash)).compactMap { review(of: $0)?.video }
        guard !waiting.isEmpty else { return }
        restoring = Task { [transcripts, weak self] in
            for video in waiting {
                // A file that moved or changed is read when it's opened again.
                guard let file = try? await VideoFile.read(URL(fileURLWithPath: video.path)),
                      file.info.contentHash == video.contentHash else { continue }
                await transcripts.start(file)
            }
            // Nothing to wait for from here on: a `wait` goes straight on.
            self?.restoring = nil
        }
    }

    /// Returns once what the last run left is ready for a listener: the
    /// transcripts of the videos whose batches wait. At once when it left
    /// nothing.
    func restored() async {
        await restoring?.value
    }

    /// Finds the images on disk of the review's comments that this run
    /// didn't write: those of an earlier run.
    private func findImages(of review: ReviewSession) {
        let hash = review.video.contentHash
        for comment in review.comments where grabs[comment.id] == nil {
            if !keyframes.contains(comment.id), Self.isFile(library.keyframeURL(hash, comment: comment.id)) {
                keyframes.insert(comment.id)
            }
            if comment.region != nil, !crops.contains(comment.id), Self.isFile(library.cropURL(hash, comment: comment.id)) {
                crops.insert(comment.id)
            }
        }
    }

    private static func isFile(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    /// Says on standard error what couldn't be kept or read, where nobody
    /// is asking who could be refused.
    private static func complain(_ line: String) {
        FileHandle.standardError.write(Data("video-review: \(line)\n".utf8))
    }

    /// Forgets a dropped comment's keyframe and crop and removes their
    /// files. An image still being written removes itself when it lands.
    private func dropImages(of id: String) {
        grabs[id] = nil
        guard let hash = session?.video.contentHash else { return }
        if keyframes.remove(id) != nil {
            try? FileManager.default.removeItem(at: library.keyframeURL(hash, comment: id))
        }
        if crops.remove(id) != nil {
            try? FileManager.default.removeItem(at: library.cropURL(hash, comment: id))
        }
    }

    // MARK: - A person's gestures

    // The window's buttons, keys and drags: the calls above, with a time
    // kept inside the video rather than refused, and nothing to answer.

    /// Opens `url`; a refusal lands in `openFailure` for the window to show.
    func openByPerson(_ url: URL) {
        Task {
            do throws(ModelRefusal) {
                try await open(url)
            } catch {
                openFailure = error.reason
            }
        }
    }

    func togglePlay() {
        if player.isPlaying {
            try? pause()
        } else {
            Task { try? await play() }
        }
    }

    /// Moves to `seconds`, kept inside the video.
    func scrub(to seconds: Double) {
        guard video != nil else { return }
        let target = min(max(0, seconds), duration)
        Task { try? await seek(to: target) }
    }

    func skip(by seconds: Double) {
        scrub(to: player.time + seconds)
    }

    /// Pauses and moves by whole frames of the open video.
    func step(frames: Int) {
        guard let video, video.frameRate > 0 else { return }
        try? pause()
        scrub(to: player.time + Double(frames) / video.frameRate)
    }

    /// Pauses and opens the comment box at the player's time, on `region`
    /// of the frame when the person drew one. With the box already open, it
    /// stays on its draft.
    func compose(region: Region? = nil) {
        guard video != nil, composing == nil else { return }
        try? pause()
        composerText = ""
        composing = try? beginComment(region: region)
    }

    /// Cmd+Enter, and the send bar's button: what the comment box holds is
    /// queued first, then the queue is sent (`sendBatch`). A refusal lands
    /// in `sendFailure` for the send bar to show.
    func sendByPerson() {
        // A second press while the first is on its way would find nothing
        // queued and say so over a send that worked.
        guard video != nil, !isSending else { return }
        if composing != nil, !composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            _ = commitComposer(text: composerText)
        }
        isSending = true
        Task {
            defer { isSending = false }
            do throws(ModelRefusal) {
                _ = try await sendBatch()
            } catch {
                sendFailure = error.reason
            }
        }
    }

    /// The person started to draw on the frame: the video pauses, so the
    /// rectangle lands on the frame they point at. False when there's
    /// nothing to draw on, or the comment box is open.
    func beginDrawing() -> Bool {
        guard video != nil, composing == nil else { return false }
        try? pause()
        return true
    }

    /// Queues what the comment box holds; false when it's refused (no
    /// text), and the box stays open.
    func commitComposer(text: String) -> Bool {
        guard let composing else { return false }
        return (try? commitComment(composing, text: text)) != nil
    }

    /// Closes the comment box and drops its draft.
    func cancelComposer() {
        guard let composing else { return }
        try? discardComment(composing)
        self.composing = nil
    }

    /// The context popover closed: the note it holds is kept.
    func noteByPerson(_ text: String) {
        try? setNote(text)
    }

    /// A click on a comment's marker or card.
    func showByPerson(_ id: String) {
        Task { try? await showComment(id) }
    }

    /// The answer box: answers the question on the comment; false when it's
    /// refused (no text), and the box keeps what it holds.
    func answerByPerson(_ commentID: String, text: String) -> Bool {
        (try? answer(commentID, text: text)) != nil
    }

    /// A click on a notice: its comment's moment shows, and the notice goes.
    func openNotice(_ notice: Notice) {
        dismissNotice(notice.id)
        if let id = notice.commentID { showByPerson(id) }
    }
}
