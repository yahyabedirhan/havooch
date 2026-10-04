import Foundation

/// The video a review is about: the hash that names it whatever its file
/// is called, and the file it was last opened from.
public struct VideoInfo: Codable, Equatable, Sendable {
    public var contentHash: String
    public var path: String
    public var title: String
    public var duration: Double

    public init(contentHash: String, path: String, title: String, duration: Double) {
        self.contentHash = contentHash
        self.path = path
        self.title = title
        self.duration = duration
    }
}

/// Everything kept for one video, and every rule that changes it. A value:
/// whoever holds it changes a copy through these methods, so a refused
/// change leaves nothing behind.
public struct Review: Codable, Equatable, Sendable {
    public var video: VideoInfo
    /// In time order; comments at the same time, in the order they were made.
    public private(set) var comments: [Comment]
    /// The number the next comment gets. It only goes up, so a deleted
    /// comment's id is never given again.
    private var nextComment: Int
    /// In the order they were sent.
    public private(set) var batches: [Batch]
    /// The number the next batch gets.
    private var nextBatch: Int
    /// The reviewer's note about the video: context a listener gets with
    /// the sidecar's text. Empty when there is none.
    public private(set) var note: String

    public init(video: VideoInfo) {
        self.video = video
        comments = []
        nextComment = 1
        batches = []
        nextBatch = 1
        note = ""
    }

    /// The comments waiting to be sent, in time order.
    public var queue: [Comment] {
        comments.filter { $0.state == .queued }
    }

    /// The comment `id` names.
    public func comment(_ id: CommentID) throws(ReviewError) -> Comment {
        guard let comment = comments.first(where: { $0.id == id }) else { throw .unknownComment(id.rawValue) }
        return comment
    }

    /// The text `addComment` would keep for a comment at `time`, or its
    /// refusal, with nothing changed: for a caller that has work to do (the
    /// keyframe) before the comment exists.
    public func checkedText(_ text: String, at time: Double) throws(ReviewError) -> String {
        let kept = try Self.kept(text)
        guard time.isFinite, (0...video.duration).contains(time) else {
            throw .timeOutsideVideo(time, duration: video.duration)
        }
        return kept
    }

    /// A new comment at `time`, straight into the queue; with `region`, on
    /// that part of the frame.
    @discardableResult
    public mutating func addComment(text: String, time: Double, region: Region? = nil, now: Date) throws(ReviewError) -> Comment {
        let comment = Comment(
            id: CommentID(contentHash: video.contentHash, number: nextComment),
            time: time, text: try checkedText(text, at: time), region: region, state: .queued, createdAt: now
        )
        nextComment += 1
        // After every comment at or before its time, so equal times keep the order they were made in.
        let index = comments.firstIndex { $0.time > time } ?? comments.endIndex
        comments.insert(comment, at: index)
        return comment
    }

    /// New text for a comment that is still queued.
    @discardableResult
    public mutating func editComment(_ id: CommentID, text: String) throws(ReviewError) -> Comment {
        let index = try queuedIndex(id)
        comments[index].text = try Self.kept(text)
        return comments[index]
    }

    /// Takes a comment that is still queued out of the review.
    public mutating func deleteComment(_ id: CommentID) throws(ReviewError) {
        comments.remove(at: try queuedIndex(id))
    }

    /// The reviewer's note is now `text`, without the blank space around
    /// it. An empty text takes the note away.
    public mutating func setNote(_ text: String) {
        note = text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Batches

    /// The batch `id` names.
    public func batch(_ id: BatchID) throws(ReviewError) -> Batch {
        guard let batch = batches.first(where: { $0.id == id }) else { throw .unknownBatch(id.rawValue) }
        return batch
    }

    /// Sends the queue as one batch: every queued comment is now `sent`
    /// and names the batch. `transcripts` are the transcript lines around
    /// each comment as they exist now. Refused when nothing is queued.
    @discardableResult
    public mutating func sendBatch(transcripts: [CommentID: [BatchPayload.Line]] = [:], now: Date) throws(ReviewError) -> Batch {
        let queued = queue.map(\.id)
        guard !queued.isEmpty else { throw .emptyQueue }
        let batch = Batch(
            id: BatchID(contentHash: video.contentHash, number: nextBatch), sentAt: now, comments: queued,
            transcripts: transcripts.filter { queued.contains($0.key) }
        )
        nextBatch += 1
        for index in comments.indices where comments[index].state == .queued {
            comments[index].state = .sent
            comments[index].batch = batch.id
        }
        batches.append(batch)
        return batch
    }

    /// Whether every comment of the batch `id` is done or failed: nothing
    /// of it is left for a listener. A batch that isn't here isn't finished.
    public func isFinished(_ id: BatchID) -> Bool {
        let sent = comments.filter { $0.batch == id }
        return !sent.isEmpty && sent.allSatisfy { $0.state == .done || $0.state == .failed }
    }

    /// The batch `id` goes to a listener again: its comments that aren't
    /// finished are `sent` once more, whatever the listener before made of
    /// them. The one move backwards a comment makes.
    public mutating func requeue(_ id: BatchID) {
        for index in comments.indices where comments[index].batch == id {
            if comments[index].state == .acknowledged || comments[index].state == .working { comments[index].state = .sent }
        }
    }

    /// Where the comment `id` names is, when it may still be changed.
    private func queuedIndex(_ id: CommentID) throws(ReviewError) -> Int {
        guard let index = comments.firstIndex(where: { $0.id == id }) else { throw .unknownComment(id.rawValue) }
        guard comments[index].state == .queued else { throw .notQueued(id, comments[index].state) }
        return index
    }

    /// `text` without the blank space around it; refused when nothing is left.
    private static func kept(_ text: String) throws(ReviewError) -> String {
        let kept = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !kept.isEmpty else { throw .emptyText }
        return kept
    }
}
