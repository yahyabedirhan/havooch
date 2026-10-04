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
        /// The part of the frame it will point at, when one was drawn.
        var region: Region?
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

    /// Opens the comment box for a comment at `time` of the video at
    /// `video`, on `region` of the frame when there is one.
    func startDraft(time: Double, region: Region?, resumes: Bool, video: URL) {
        endDraft()
        draft = Draft(time: time, region: region, resumes: resumes, frame: Task { await Self.frame(of: video, at: time) })
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
        publish(review)
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
        let prefix = id.rawValue.prefix(VideoPrefix.length)
        return reviews.keys.first { $0.hasPrefix(prefix) } ?? String(prefix)
    }

    private func publish(_ review: Review) {
        reviews[review.video.contentHash] = review
        if open?.video.contentHash == review.video.contentHash { open = review }
    }
}
