import Foundation
import VRReview

/// The support folder as the app keeps things in it: where each file is, the
/// numbers ids are made from, and which video an id belongs to.
///
///     index.json                             the next comment and batch numbers; comment id → hash; batch id → hash
///     outbox.json                            the batches sent and not finished
///     videos/<contentHash>/review.json       the video's review
///     videos/<contentHash>/frames/<id>.png   a comment's keyframe
///     videos/<contentHash>/crops/<id>.png    the crop of a comment's region
///
/// Every file is replaced whole in one step on each write, so a crash leaves
/// the last full version of it.
public struct Library: Sendable {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    // MARK: - Reviews

    /// The review kept for the video `hash`, or nil when none was kept.
    public func session(for hash: String) throws -> ReviewSession? {
        try JSONFile.read(ReviewSession.self, at: reviewFile(hash))
    }

    /// Keeps the review, without its drafts, and the index's record of which
    /// comments and batches are this video's. The index is written first: an
    /// id it names that the review doesn't have yet is found by nobody, while
    /// a comment the index doesn't name couldn't be answered by a listener.
    public func save(_ session: ReviewSession) throws {
        let kept = session.kept
        let hash = kept.video.contentHash
        let index = try JSONFile.read(Index.self, at: indexFile) ?? Index()
        var changed = index
        changed.comments = index.comments.filter { $0.value != hash }
        for comment in kept.comments { changed.comments[comment.id] = hash }
        changed.batches = index.batches.filter { $0.value != hash }
        for batch in kept.batches { changed.batches[batch.id] = hash }
        if changed != index { try JSONFile.write(changed, to: indexFile) }
        try JSONFile.write(kept, to: reviewFile(hash))
    }

    /// The video whose review has the comment `id`, or nil when no kept
    /// review has it, or the index can't be read.
    public func videoHash(forComment id: String) -> String? {
        index?.comments[id]
    }

    /// The video whose review has the batch `id`.
    public func videoHash(forBatch id: String) -> String? {
        index?.batches[id]
    }

    // MARK: - The outbox

    /// The outbox with the parcels that were kept; an empty one when none
    /// were.
    public func outbox() throws -> Outbox {
        Outbox(parcels: try JSONFile.read([Outbox.Parcel].self, at: outboxFile) ?? [])
    }

    /// Keeps the outbox's parcels. Its listener isn't kept.
    public func save(_ outbox: Outbox) throws {
        try JSONFile.write(outbox.parcels, to: outboxFile)
    }

    // MARK: - Ids

    /// The next comment id: `c1`, `c2`, … across every video of this
    /// library, so an id names one comment wherever it's used. The number is
    /// kept in `index.json`; an id given out is never given again, also when
    /// its comment was dropped.
    public func nextCommentID() throws -> String {
        var index = try JSONFile.read(Index.self, at: indexFile) ?? Index()
        let id = "c\(index.nextComment)"
        index.nextComment += 1
        try JSONFile.write(index, to: indexFile)
        return id
    }

    /// The next batch id: `b1`, `b2`, … across every video of this library,
    /// kept as the comment numbers are.
    public func nextBatchID() throws -> String {
        var index = try JSONFile.read(Index.self, at: indexFile) ?? Index()
        let id = "b\(index.nextBatch)"
        index.nextBatch += 1
        try JSONFile.write(index, to: indexFile)
        return id
    }

    // MARK: - Images

    /// Where the keyframe of the comment `comment` on the video `hash` is.
    public func keyframeURL(_ hash: String, comment: String) -> URL {
        image("frames", hash, comment: comment)
    }

    /// Where the crop of the region of the comment `comment` on the video
    /// `hash` is.
    public func cropURL(_ hash: String, comment: String) -> URL {
        image("crops", hash, comment: comment)
    }

    /// Removes the keyframes and crops of the video `hash` that belong to
    /// none of the comments `ids`: what a draft left when the app quit with
    /// its comment box open.
    public func removeImages(of hash: String, keeping ids: Set<String>) {
        for folder in ["frames", "crops"] {
            let folder = videoFolder(hash).appendingPathComponent(folder, isDirectory: true)
            let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            for file in files where file.pathExtension == "png" && !ids.contains(file.deletingPathExtension().lastPathComponent) {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    private func image(_ folder: String, _ hash: String, comment: String) -> URL {
        videoFolder(hash)
            .appendingPathComponent(folder, isDirectory: true)
            .appendingPathComponent(comment + ".png")
    }

    private func videoFolder(_ hash: String) -> URL {
        root
            .appendingPathComponent("videos", isDirectory: true)
            .appendingPathComponent(hash, isDirectory: true)
    }

    private func reviewFile(_ hash: String) -> URL {
        videoFolder(hash).appendingPathComponent("review.json")
    }

    private var outboxFile: URL {
        root.appendingPathComponent("outbox.json")
    }

    private var indexFile: URL {
        root.appendingPathComponent("index.json")
    }

    private var index: Index? {
        (try? JSONFile.read(Index.self, at: indexFile)) ?? nil
    }

    private struct Index: Codable, Equatable {
        var nextComment = 1
        var nextBatch = 1
        /// The video each kept comment belongs to, by the comment's id.
        var comments: [String: String] = [:]
        /// The video each batch was sent from, by the batch's id.
        var batches: [String: String] = [:]

        init() {}

        /// An index written before batches were numbered has no batch
        /// number, and one written before reviews were kept names no ids.
        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            nextComment = try container.decodeIfPresent(Int.self, forKey: .nextComment) ?? 1
            nextBatch = try container.decodeIfPresent(Int.self, forKey: .nextBatch) ?? 1
            comments = try container.decodeIfPresent([String: String].self, forKey: .comments) ?? [:]
            batches = try container.decodeIfPresent([String: String].self, forKey: .batches) ?? [:]
        }
    }
}
