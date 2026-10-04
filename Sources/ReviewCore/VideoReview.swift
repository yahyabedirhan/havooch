import Foundation

/// The video a review is about. Its identity is the hash of its content, so
/// a renamed or moved file is the same video.
public struct VideoInfo: Codable, Equatable, Sendable {
    public var contentHash: String
    /// The file's name without its extension.
    public var title: String
    /// The length in seconds.
    public var duration: TimeInterval
    /// Where the file was when it was last opened.
    public var path: String

    public init(contentHash: String, title: String, duration: TimeInterval, path: String) {
        self.contentHash = contentHash
        self.title = title
        self.duration = duration
        self.path = path
    }
}

/// Everything kept about one video, and every rule about its comments. Ids
/// come in as arguments, so a test names them.
public struct VideoReview: Codable, Equatable, Sendable {
    public var video: VideoInfo
    /// The comments in time order; two at the same time stay in the order
    /// they were added.
    public private(set) var comments: [Comment]
    /// The batches, in the order they were sent.
    public private(set) var batches: [Batch]

    public init(video: VideoInfo) {
        self.video = video
        comments = []
        batches = []
    }

    /// The comments waiting to be sent, in time order.
    public var queue: [Comment] {
        comments.filter { $0.state == .queued }
    }

    public func comment(_ id: ItemID) -> Comment? {
        comments.first { $0.id == id }
    }

    /// Queues a comment at `time`, on `region` of the frame when it has
    /// one. The text loses the space around it; a text with no words is
    /// refused.
    @discardableResult
    public mutating func addComment(
        id: ItemID, time: TimeInterval, text: String, region: Region? = nil
    ) throws(ReviewRefusal) -> Comment {
        let comment = Comment(id: id, time: time, text: try Self.words(text), state: .queued, region: region)
        let index = comments.firstIndex { $0.time > time } ?? comments.endIndex
        comments.insert(comment, at: index)
        return comment
    }

    /// Replaces a queued comment's text.
    @discardableResult
    public mutating func editComment(_ id: ItemID, text: String) throws(ReviewRefusal) -> Comment {
        let index = try queuedIndex(id)
        comments[index].text = try Self.words(text)
        return comments[index]
    }

    /// Removes a queued comment.
    @discardableResult
    public mutating func deleteComment(_ id: ItemID) throws(ReviewRefusal) -> Comment {
        comments.remove(at: try queuedIndex(id))
    }

    // MARK: - Batches

    public func batch(_ id: ItemID) -> Batch? {
        batches.first { $0.id == id }
    }

    /// The comments of the batch `id`, in time order.
    public func comments(of id: ItemID) -> [Comment] {
        comments.filter { $0.batchID == id }
    }

    /// Sends every queued comment as one batch: each moves to `sent` and
    /// names the batch. Refused when nothing is queued.
    @discardableResult
    public mutating func send(batchID: ItemID, at now: Date) throws(ReviewRefusal) -> Batch {
        let queued = comments.indices.filter { comments[$0].state == .queued }
        guard !queued.isEmpty else { throw .nothingQueued }
        for index in queued {
            comments[index].state = .sent
            comments[index].batchID = batchID
        }
        let batch = Batch(id: batchID, sentAt: now, commentIDs: queued.map { comments[$0].id })
        batches.append(batch)
        return batch
    }

    /// Whether the listener has nothing left to do on the batch `id`:
    /// every comment in it is `done` or `failed`. A batch the review
    /// doesn't have counts as finished.
    public func isFinished(_ id: ItemID) -> Bool {
        comments(of: id).allSatisfy(\.state.isFinal)
    }

    /// The batch `id` goes back to the listener's queue, since the
    /// listener that took it is gone: its unfinished comments return to
    /// `sent`, the one move back the states allow. Finished comments stay
    /// as they are. Returns the comments that are to be delivered again.
    @discardableResult
    public mutating func requeue(_ id: ItemID) -> [ItemID] {
        let unfinished = comments.indices.filter { comments[$0].batchID == id && !comments[$0].state.isFinal }
        for index in unfinished { comments[index].state = .sent }
        return unfinished.map { comments[$0].id }
    }

    private func queuedIndex(_ id: ItemID) throws(ReviewRefusal) -> Int {
        guard let index = comments.firstIndex(where: { $0.id == id }) else { throw .unknownComment(id.text) }
        guard comments[index].state.isEditable else { throw .notQueued(id, comments[index].state) }
        return index
    }

    private static func words(_ text: String) throws(ReviewRefusal) -> String {
        let words = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty else { throw .emptyText }
        return words
    }
}
