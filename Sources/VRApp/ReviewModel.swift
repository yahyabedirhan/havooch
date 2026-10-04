import Foundation
import Observation
import VRReview
import VRStore

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

    @ObservationIgnored private let player: any Playing
    @ObservationIgnored private let frames: any FrameGrabbing
    @ObservationIgnored private let library: Library
    /// Each comment's keyframe being written: nil once it's on disk, or why
    /// it couldn't be saved.
    @ObservationIgnored private var grabs: [String: Task<String?, Never>] = [:]
    /// The reviews of the videos opened earlier in this run, by content
    /// hash, so a video opened again has its comments. The store takes this
    /// over when reviews are kept on disk.
    @ObservationIgnored private var shelved: [String: ReviewSession] = [:]

    init(player: any Playing, frames: any FrameGrabbing, library: Library, demoFolder: URL? = nil) {
        self.player = player
        self.frames = frames
        self.library = library
        self.demoFolder = demoFolder
    }

    var time: Double { player.time }
    var isPlaying: Bool { player.isPlaying }
    /// The open video's length in seconds; 0 with none.
    var duration: Double { video?.info.duration ?? 0 }
    /// The open video's comments that were written, in time order: what the
    /// timeline marks and the sidebar lists. A draft isn't among them.
    var comments: [Comment] { session?.comments.filter { $0.state != .draft } ?? [] }

    /// Where the keyframe of the comment `id` is, or nil while it isn't on
    /// disk.
    func keyframeURL(for id: String) -> URL? {
        guard keyframes.contains(id), let session else { return nil }
        return library.keyframeURL(session.video.contentHash, comment: id)
    }

    // MARK: - What a person and an operator can do

    /// Opens the video at `url`, paused at its start. A file the player
    /// can't play is refused with the reason, and the open video stays.
    func open(_ url: URL) async throws(ModelRefusal) {
        let file = try await VideoFile.read(url)
        do {
            try await player.load(url)
        } catch {
            throw ModelRefusal("couldn't open \(url.path): \(error.localizedDescription)")
        }
        cancelComposer()
        if let session { shelved[session.video.contentHash] = session }
        var opened = shelved[file.info.contentHash] ?? ReviewSession(video: file.info)
        // The file may have moved since: the review keeps the last path seen.
        opened.video = file.info
        session = opened
        selection = nil
        video = file
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

    /// Starts a comment at `seconds`, or at the player's time: a draft with
    /// its time, whose keyframe starts being written from the video file.
    /// Returns the draft's id, for `commitComment` or `discardComment`.
    func beginComment(at seconds: Double? = nil) throws(ModelRefusal) -> String {
        let video = try openVideo()
        if let seconds { try inside(seconds, of: video) }
        let time = TimeText.rounded(min(max(0, seconds ?? player.time), video.info.duration))
        let id: String
        do {
            id = try library.nextCommentID()
        } catch {
            throw ModelRefusal("couldn't number the comment: \(error.localizedDescription)")
        }
        session?.draft(id: id, time: time)
        let hash = video.info.contentHash
        let file = library.keyframeURL(hash, comment: id)
        grabs[id] = Task { [frames, weak self] in
            do {
                _ = try await frames.writeKeyframe(of: video.url, at: time, to: file)
            } catch {
                return error.localizedDescription
            }
            // The comment may have been dropped while its frame was written.
            if let self, self.review(of: hash)?.comment(id) != nil {
                self.keyframes.insert(id)
            } else {
                try? FileManager.default.removeItem(at: file)
            }
            return nil
        }
        return id
    }

    /// Gives the draft `id` its text and queues it.
    func commitComment(_ id: String, text: String) throws(ModelRefusal) {
        try change { (session) throws(ReviewRefusal) in try session.commit(id, text: text) }
        if composing == id { composing = nil }
        selection = id
    }

    /// Drops the draft `id` and its keyframe.
    func discardComment(_ id: String) throws(ModelRefusal) {
        try change { (session) throws(ReviewRefusal) in try session.discard(id) }
        if composing == id { composing = nil }
        dropKeyframe(of: id)
    }

    /// Queues a comment in one step, as the command line does: the video is
    /// paused, and moved to `seconds` first when it's given, so the window
    /// shows what was commented on. Returns once the keyframe is on disk; a
    /// frame that can't be saved refuses the comment.
    func addComment(text: String, at seconds: Double? = nil) async throws(ModelRefusal) -> Comment {
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
        let id = try beginComment(at: seconds)
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

    /// Takes a queued comment out, with its keyframe.
    func deleteComment(_ id: String) throws(ModelRefusal) {
        try change { (session) throws(ReviewRefusal) in try session.delete(id) }
        if selection == id { selection = nil }
        dropKeyframe(of: id)
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
        _ = try openVideo()
        guard var changed = session else { return }
        do throws(ReviewRefusal) {
            try body(&changed)
        } catch {
            throw ModelRefusal(error.reason)
        }
        session = changed
    }

    /// The review of the video `hash`: the open one, or one opened earlier.
    private func review(of hash: String) -> ReviewSession? {
        session?.video.contentHash == hash ? session : shelved[hash]
    }

    /// Forgets a dropped comment's keyframe and removes its file. A frame
    /// still being written removes itself when it lands.
    private func dropKeyframe(of id: String) {
        grabs[id] = nil
        guard keyframes.remove(id) != nil, let session else { return }
        try? FileManager.default.removeItem(at: library.keyframeURL(session.video.contentHash, comment: id))
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

    /// Pauses and opens the comment box at the player's time. With the box
    /// already open, it stays on its draft.
    func compose() {
        guard video != nil, composing == nil else { return }
        try? pause()
        composing = try? beginComment()
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

    /// A click on a comment's marker or card.
    func showByPerson(_ id: String) {
        Task { try? await showComment(id) }
    }
}
