import CoreGraphics
import Foundation
import Observation
import VRReview
import VRStore

/// The reviews in memory, by content hash, and the comment being typed.
/// A review changes only here: a copy is changed through the review's own
/// methods, its keyframe written, and only then is it published, so a
/// refused change leaves nothing behind.
@MainActor @Observable
final class ReviewDesk {
    /// The comment being typed: it has no id until it is queued.
    struct Draft {
        /// The time it will be about: where the video was paused.
        var time: Double
        /// Whether the video was playing when the comment box opened, and
        /// so plays again once the comment is queued.
        var resumes: Bool
        /// The frame at `time`, read from the moment the box opens, so
        /// Return doesn't wait for it.
        var frame: Task<Result<CGImage, FrameFailure>, Never>
    }

    /// The open video's review.
    private(set) var open: Review?
    private(set) var draft: Draft?
    let layout: SupportLayout
    private var reviews: [String: Review] = [:]

    init(layout: SupportLayout) {
        self.layout = layout
    }

    /// The review of `video`, now the open one: the one kept under its
    /// content hash, with the file it was opened from this time, or a new one.
    @discardableResult
    func load(_ video: VideoInfo) -> Review {
        var review = reviews[video.contentHash] ?? Review(video: video)
        review.video = video
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

    /// Opens the comment box for a comment at `time` of the video at `video`.
    func startDraft(time: Double, resumes: Bool, video: URL) {
        endDraft()
        draft = Draft(time: time, resumes: resumes, frame: Task { await Self.frame(of: video, at: time) })
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
    /// keyframe. The comment exists only once its keyframe is on disk.
    func add(text: String, time: Double, frame: CGImage, to hash: String) throws(ActionError) -> Comment {
        guard var review = reviews[hash] else { throw .noVideo }
        let comment: Comment
        do throws(ReviewError) {
            comment = try review.addComment(text: text, time: time, now: Date())
        } catch {
            throw .review(error)
        }
        do throws(FrameFailure) {
            try FrameGrabber.write(frame, to: layout.keyframe(comment.id, of: hash))
        } catch {
            throw .keyframe(error.why)
        }
        publish(review)
        return comment
    }

    /// Takes the queued comment `id` out of the video `hash` names, and its keyframe with it.
    func delete(_ id: CommentID, from hash: String) throws(ActionError) {
        try change(hash) { review throws(ReviewError) in try review.deleteComment(id) }
        try? FileManager.default.removeItem(at: layout.keyframe(id, of: hash))
    }

    /// The one way a review changes: `body` changes a copy through the
    /// review's own methods, and the copy is published when nothing was
    /// refused.
    func change<T>(_ hash: String, _ body: (inout Review) throws(ReviewError) -> T) throws(ActionError) -> T {
        guard var review = reviews[hash] else { throw .noVideo }
        let result: T
        do throws(ReviewError) {
            result = try body(&review)
        } catch {
            throw .review(error)
        }
        publish(review)
        return result
    }

    /// Where the keyframe of the comment `id` is: in the folder of the
    /// video its id names. An id that names no video here gets a path with
    /// nothing at it.
    func keyframe(of id: CommentID) -> URL {
        let prefix = id.rawValue.prefix(VideoPrefix.length)
        return layout.keyframe(id, of: reviews.keys.first { $0.hasPrefix(prefix) } ?? String(prefix))
    }

    private func publish(_ review: Review) {
        reviews[review.video.contentHash] = review
        if open?.video.contentHash == review.video.contentHash { open = review }
    }
}
