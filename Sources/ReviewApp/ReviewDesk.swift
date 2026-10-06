import Foundation
import Observation
import ReviewCore
import ReviewStore

/// The one path for changing a review: take a video's review, run the
/// change, save it, publish it to the views. A refused change, and one
/// that can't be saved, leaves the review as it was, in memory and on disk.
///
/// A review is read from the `Library` the first time it's asked for and
/// kept in memory from then on, by content hash, so a send of a video
/// that's not open, or wasn't opened in this run, can still be delivered
/// and answered.
@Observable
final class ReviewDesk {
    /// The open video's review; nil with no video.
    private(set) var review: VideoReview?
    /// The reviews this run has read or made, by content hash.
    @ObservationIgnored private var reviews: [String: VideoReview] = [:]
    @ObservationIgnored let library: Library

    init(library: Library) {
        self.library = library
    }

    /// The review `video` opens on: the one kept for its content, or a new
    /// one. Refused when the kept one doesn't read; nothing changes, and
    /// nothing is written over it.
    func review(for video: VideoInfo) throws(AppRefusal) -> VideoReview {
        try kept(video.contentHash) ?? VideoReview(video: video)
    }

    /// Makes `review` the open one, as `review(for:)` gave it. A review
    /// that's on disk is saved when its video moved or was renamed; a new
    /// one is first saved with its first change.
    func open(_ review: VideoReview) {
        let hash = review.video.contentHash
        let isKept = FileManager.default.fileExists(atPath: library.layout.reviewFile(hash).path)
        if isKept, reviews[hash] != review {
            // Not being able to record the new path doesn't keep the video shut.
            try? library.save(review)
        }
        reviews[hash] = review
        self.review = review
    }

    /// No review is the open one: the video closed. Its review stays kept,
    /// so a listener can still answer on it.
    func close() {
        review = nil
    }

    /// The review of the video with `contentHash`, open or not; nil when
    /// there's none, or it doesn't read.
    func review(of contentHash: String) -> VideoReview? {
        try? kept(contentHash)
    }

    /// The content hash of the video the thread, message or send `id` is
    /// on, by its prefix; nil when no review is that video's. A listener's command names
    /// an id and no video.
    func contentHash(of id: ItemID) -> String? {
        library.contentHash(of: id)
    }

    /// The thread a command names, and its video's content hash: a full id
    /// names its video by its prefix, a bare number is the open video's
    /// (`0` is General). Refused for what isn't a thread of a review.
    func threadID(_ text: String) throws(AppRefusal) -> (ThreadID, String) {
        let ref = ThreadRef(text)
        let hash: String? = switch ref {
        case .id(let id): contentHash(of: id)
        case .number: review?.video.contentHash
        case nil: nil
        }
        guard let ref, let hash, let review = review(of: hash) else {
            throw AppRefusal(
                "no thread `\(text)`; give a thread id from the send `havooch wait` printed, or a number of the open video"
            )
        }
        do throws(ReviewRefusal) {
            return (try review.threadID(ref), hash)
        } catch {
            throw AppRefusal(error.line)
        }
    }

    /// Runs `change` on the open review, saves and publishes the result.
    func change<Result>(_ change: (inout VideoReview) throws(ReviewRefusal) -> Result) throws(AppRefusal) -> Result {
        guard let review else {
            throw AppRefusal("no video is open; open one with `havooch player open <path>`")
        }
        return try self.change(review.video.contentHash, change)
    }

    /// Runs `change` on the review of the video with `contentHash`, open
    /// or not, saves it, and publishes the result when it's the open one.
    func change<Result>(
        _ contentHash: String, _ change: (inout VideoReview) throws(ReviewRefusal) -> Result
    ) throws(AppRefusal) -> Result {
        guard var changed = try kept(contentHash) else {
            throw AppRefusal("there's no review of the video \(contentHash)")
        }
        let before = changed
        let result: Result
        do throws(ReviewRefusal) {
            result = try change(&changed)
        } catch {
            throw AppRefusal(error.line)
        }
        guard changed != before else { return result }
        do throws(Library.Failure) {
            try library.save(changed)
        } catch {
            throw AppRefusal("nothing changed: \(error.reason)")
        }
        reviews[contentHash] = changed
        if review?.video.contentHash == contentHash { review = changed }
        return result
    }

    /// The review of the video with `contentHash`: this run's, else the
    /// one on disk, which this run then has.
    private func kept(_ contentHash: String) throws(AppRefusal) -> VideoReview? {
        if let review = reviews[contentHash] { return review }
        do throws(Library.Failure) {
            let review = try library.load(contentHash)
            reviews[contentHash] = review
            return review
        } catch {
            throw AppRefusal(error.reason)
        }
    }
}
