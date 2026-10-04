import CoreGraphics
import Foundation
import Observation
import VRReview
import VRStore

/// The reviews, by content hash, and the comment being typed. Every review
/// under the support folder is read once, as the desk is made; from then
/// on the desk's copy is the one that counts, and the files follow it.
/// A review changes only here: a copy is changed through the review's own
/// methods, its keyframe written, the copy saved, and only then is it
/// published, so a refused change leaves nothing behind and nothing is
/// shown that isn't on disk.
@MainActor @Observable
final class ReviewDesk {
    /// The comment being typed: it has no id until it is queued.
    struct Draft {
        /// The time it will be about: where the video was paused.
        var time: Double
        /// The part of the frame it will point at, when one was drawn.
        var region: Region?
        /// Whether the video was playing when the comment box opened, and
        /// so plays again once the comment is queued.
        var resumes: Bool
        /// The frame at `time`, read from the moment the box opens, so
        /// Return doesn't wait for it.
        var frame: Task<Result<CGImage, FrameFailure>, Never>
        /// What is typed in the comment box so far: here, not in the box,
        /// so a send from anywhere can queue it first.
        var text = ""
    }

    /// The open video's review.
    private(set) var open: Review?
    private(set) var draft: Draft?
    let layout: SupportLayout
    let store: ReviewStore
    private var reviews: [String: Review]
    /// The reviews whose last change was typed and isn't saved yet.
    @ObservationIgnored private var unsaved: Set<String> = []
    /// Saves them once the typing rests.
    @ObservationIgnored private var settling: Task<Void, Never>?

    /// How long after the last key a typed change is saved.
    static let rest = Duration.milliseconds(600)

    init(layout: SupportLayout) {
        self.layout = layout
        store = ReviewStore(layout: layout)
        reviews = Dictionary(store.loadReviews().map { ($0.video.contentHash, $0) }) { first, _ in first }
    }

    /// Every review there is, open or not, in the order of their hashes.
    var all: [Review] {
        reviews.values.sorted { $0.video.contentHash < $1.video.contentHash }
    }

    /// The review of `video`, now the open one: the one kept under its
    /// content hash, with the file it was opened from this time, or a new
    /// one. A new one is in no file until its first change.
    @discardableResult
    func load(_ video: VideoInfo) -> Review {
        var review = reviews[video.contentHash] ?? Review(video: video)
        if review.video != video {
            // A renamed or moved copy: the history is the hash's, the path the file's.
            review.video = video
            // A new path that can't be saved now is saved with the review's next change.
            if reviews[video.contentHash] != nil { try? store.save(review) }
        }
        reviews[video.contentHash] = review
        open = review
        endDraft()
        return review
    }

    /// No video is open any more.
    func close() {
        open = nil
        endDraft()
    }

    /// Opens the comment box for a comment at `time` of the video at
    /// `video`, on `region` of the frame when there is one.
    /// A box that was open keeps what was typed in it.
    func startDraft(time: Double, region: Region?, resumes: Bool, video: URL) {
        let typed = draft?.text ?? ""
        endDraft()
        draft = Draft(time: time, region: region, resumes: resumes, frame: Task { await Self.frame(of: video, at: time) }, text: typed)
    }

    /// The comment box's text is now `text`.
    func typeDraft(_ text: String) {
        draft?.text = text
    }

    /// The comment being typed now points at `region`.
    func pointDraft(at region: Region?) {
        draft?.region = region
    }

    /// Closes the comment box.
    func endDraft() {
        draft?.frame.cancel()
        draft = nil
    }

    /// The frame of `video` at `time`, or why it can't be read.
    nonisolated static func frame(of video: URL, at time: Double) async -> Result<CGImage, FrameFailure> {
        do throws(FrameFailure) {
            return .success(try await FrameGrabber.frame(of: video, at: time))
        } catch {
            return .failure(error)
        }
    }

    /// A new queued comment on the video `hash` names, with `frame` as its
    /// keyframe and, with a `region`, that part of `frame` as its crop. The
    /// comment exists only once its files are on disk.
    func add(text: String, time: Double, region: Region?, frame: CGImage, to hash: String) throws(ActionError) -> Comment {
        guard var review = reviews[hash] else { throw .noVideo }
        let comment: Comment
        do throws(ReviewError) {
            comment = try review.addComment(text: text, time: time, region: region, now: Date())
        } catch {
            throw .review(error)
        }
        do throws(FrameFailure) {
            try FrameGrabber.write(frame, to: layout.keyframe(comment.id, of: hash))
        } catch {
            throw .keyframe(error.why)
        }
        if let region {
            do throws(FrameFailure) {
                try FrameGrabber.write(try FrameGrabber.crop(frame, to: region), to: layout.crop(comment.id, of: hash))
            } catch {
                throw .crop(error.why)
            }
        }
        try keep(review)
        return comment
    }

    /// Takes the queued comment `id` out of the video `hash` names, and its
    /// keyframe and its crop with it.
    func delete(_ id: CommentID, from hash: String) throws(ActionError) {
        try change(hash) { review throws(ReviewError) in try review.deleteComment(id) }
        try? FileManager.default.removeItem(at: layout.keyframe(id, of: hash))
        try? FileManager.default.removeItem(at: layout.crop(id, of: hash))
    }

    /// The one way a review changes: `body` changes a copy through the
    /// review's own methods, and the copy is saved and then published when
    /// nothing was refused. A copy that can't be saved is a refusal too.
    func change<T>(_ hash: String, _ body: (inout Review) throws(ReviewError) -> T) throws(ActionError) -> T {
        guard var review = reviews[hash] else { throw .noVideo }
        let result: T
        do throws(ReviewError) {
            result = try body(&review)
        } catch {
            throw .review(error)
        }
        // A change that changed nothing (a second acknowledgement) writes nothing.
        if review != reviews[hash] || unsaved.contains(hash) { try keep(review) }
        return result
    }

    /// A change that is typed, a key at a time (the note): published at
    /// once, and saved when the typing has rested for `rest`, or at the
    /// review's next change, or at `settle`, whichever comes first.
    func changeTyped(_ hash: String, _ body: (inout Review) -> Void) throws(ActionError) {
        guard var review = reviews[hash] else { throw .noVideo }
        body(&review)
        guard review != reviews[hash] else { return }
        publish(review)
        unsaved.insert(hash)
        settling?.cancel()
        settling = Task { [weak self] in
            do { try await Task.sleep(for: Self.rest) } catch { return }
            self?.settle()
        }
    }

    /// Saves what was typed and isn't saved yet: the typing rested, its
    /// box closed, or the app quits. A review that can't be saved now is
    /// tried again at the next call.
    func settle() {
        settling?.cancel()
        settling = nil
        for hash in unsaved {
            guard let review = reviews[hash] else { continue }
            do {
                try store.save(review)
                unsaved.remove(hash)
            } catch {
                NSLog("video-review: can't keep the review of %@: %@", review.video.path, error.localizedDescription)
            }
        }
    }

    /// Saves `review`, then publishes it.
    private func keep(_ review: Review) throws(ActionError) {
        do {
            try store.save(review)
        } catch {
            throw .store(error.localizedDescription)
        }
        unsaved.remove(review.video.contentHash)
        publish(review)
    }

    /// The review of the video `hash` names, open or not; nil when no such
    /// video was ever commented on here.
    func review(_ hash: String) -> Review? {
        reviews[hash]
    }

    /// Where the keyframe of the comment `id` is: in the folder of the
    /// video its id names. An id that names no video here gets a path with
    /// nothing at it.
    func keyframe(of id: CommentID) -> URL {
        layout.keyframe(id, of: hash(named: id))
    }

    /// Where the crop of the comment `id` is, beside its keyframe. Only a
    /// comment with a region has a file there.
    func crop(of id: CommentID) -> URL {
        layout.crop(id, of: hash(named: id))
    }

    /// The content hash of the video `id` names by its first digits, or
    /// those digits alone when no video here has them.
    private func hash(named id: CommentID) -> String {
        hash(naming: id.rawValue) ?? String(id.rawValue.prefix(VideoPrefix.length))
    }

    /// The content hash of the video a comment's or a batch's `id` names
    /// by its first digits, open or not; nil when there is no such video
    /// here. It is how a listener's command finds its review whatever
    /// video is open, in this run or after a restart.
    func hash(naming id: String) -> String? {
        let prefix = id.prefix(VideoPrefix.length)
        guard prefix.count == VideoPrefix.length else { return nil }
        return reviews.keys.first { $0.hasPrefix(prefix) }
    }

    private func publish(_ review: Review) {
        reviews[review.video.contentHash] = review
        if open?.video.contentHash == review.video.contentHash { open = review }
    }
}
