import Observation
import ReviewCore

/// The one path for changing a review: take a video's review, run the
/// change, publish it to the views. A refused change leaves the review as
/// it was.
///
/// Reviews are kept in memory for as long as the app runs, by content hash,
/// so a video that opens again in the same run has its comments back, and a
/// batch of a video that's no longer open can still be delivered.
@MainActor
@Observable
final class ReviewDesk {
    /// The open video's review; nil with no video.
    private(set) var review: VideoReview?
    /// Every review of this run, by content hash.
    @ObservationIgnored private var reviews: [String: VideoReview] = [:]

    /// Makes `video`'s review the open one: the one this run already has
    /// for its content, or a new one.
    func open(_ video: VideoInfo) {
        var review = reviews[video.contentHash] ?? VideoReview(video: video)
        // The same content at a new path or under a new name.
        review.video = video
        reviews[video.contentHash] = review
        self.review = review
    }

    /// The review of the video with `contentHash`, open or not.
    func review(of contentHash: String) -> VideoReview? {
        reviews[contentHash]
    }

    /// Runs `change` on the open review and publishes the result.
    func change<Result>(_ change: (inout VideoReview) throws(ReviewRefusal) -> Result) throws(AppRefusal) -> Result {
        guard let review else {
            throw AppRefusal("no video is open; open one with `video-review player open <path>`")
        }
        return try self.change(review.video.contentHash, change)
    }

    /// Runs `change` on the review of the video with `contentHash`, open
    /// or not, and publishes the result when it's the open one.
    func change<Result>(
        _ contentHash: String, _ change: (inout VideoReview) throws(ReviewRefusal) -> Result
    ) throws(AppRefusal) -> Result {
        guard var changed = reviews[contentHash] else {
            throw AppRefusal("this run has no review of the video \(contentHash)")
        }
        let result: Result
        do throws(ReviewRefusal) {
            result = try change(&changed)
        } catch {
            throw AppRefusal(error.line)
        }
        reviews[contentHash] = changed
        if review?.video.contentHash == contentHash { review = changed }
        return result
    }
}
