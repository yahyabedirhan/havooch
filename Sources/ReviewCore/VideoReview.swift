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
    /// Frames a second, as the player read it when the video was last
    /// opened; nil in a review kept before this was. A `voiceover.json`'s
    /// scene times need it, also for a batch that's delivered in a run
    /// that didn't open the video.
    public var frameRate: Double?

    public init(contentHash: String, title: String, duration: TimeInterval, path: String, frameRate: Double? = nil) {
        self.contentHash = contentHash
        self.title = title
        self.duration = duration
        self.path = path
        self.frameRate = frameRate
    }
}

/// Everything kept about one video, and every rule about its comments. Ids
/// come in as arguments, so a test names them.
public struct VideoReview: Codable, Equatable, Sendable {
    public var video: VideoInfo
    /// The person's context note for the agent, added to the sidecar's
    /// text; empty for none.
    public var note = ""
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

    private enum CodingKeys: String, CodingKey {
        case video, note, comments, batches
    }

    /// Reads a review; one written before there was a note has none.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        video = try container.decode(VideoInfo.self, forKey: .video)
        note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
        comments = try container.decode([Comment].self, forKey: .comments)
        batches = try container.decode([Batch].self, forKey: .batches)
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
        let batch = Batch(id: batchID, sentAt: Self.kept(now), commentIDs: queued.map { comments[$0].id })
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

    // MARK: - The listener's answers

    /// The listener has the batch `id`: each of its comments still `sent`
    /// moves to `acknowledged`, and one further on stays where it is. Words
    /// that come with it are a message for the full batch. Returns the
    /// batch as it is now.
    @discardableResult
    public mutating func acknowledge(
        _ id: ItemID, text: String? = nil, messageID: ItemID, at now: Date
    ) throws(ReviewRefusal) -> Batch {
        let batch = try batchIndex(id)
        for index in comments.indices where comments[index].batchID == id && comments[index].state == .sent {
            comments[index].state = .acknowledged
        }
        if let words = text?.trimmingCharacters(in: .whitespacesAndNewlines), !words.isEmpty {
            batches[batch].messages.append(ThreadMessage(id: messageID, author: .agent, kind: .message, text: words, at: Self.kept(now)))
        }
        return batches[batch]
    }

    /// The listener says how far it is with a comment: `working`, `done`
    /// or `failed`. A state only moves forward and may skip one; `done` and
    /// `failed` are final. Saying the state the comment already has changes
    /// nothing and isn't refused.
    @discardableResult
    public mutating func setStatus(_ id: ItemID, _ state: CommentState) throws(ReviewRefusal) -> Comment {
        let index = try sentIndex(id)
        let from = comments[index].state
        guard from != state else { return comments[index] }
        guard state.isStatus, from.canMove(to: state) else { throw .illegalMove(id, from: from, to: state) }
        comments[index].state = state
        return comments[index]
    }

    /// The agent's message on a comment's thread, or for the full batch
    /// when `id` names a batch.
    @discardableResult
    public mutating func reply(to id: ItemID, text: String, messageID: ItemID, at now: Date) throws(ReviewRefusal) -> ThreadMessage {
        let message = ThreadMessage(id: messageID, author: .agent, kind: .message, text: try Self.message(text), at: Self.kept(now))
        if id.kind == .batch {
            batches[try batchIndex(id)].messages.append(message)
        } else {
            comments[try sentIndex(id)].thread.append(message)
        }
        return message
    }

    /// The agent's question on a comment's thread. Refused while the
    /// comment has a question with no answer: an answer names a comment, so
    /// it must have one question to go to.
    @discardableResult
    public mutating func ask(_ id: ItemID, question: String, messageID: ItemID, at now: Date) throws(ReviewRefusal) -> ThreadMessage {
        let index = try sentIndex(id)
        let message = ThreadMessage(id: messageID, author: .agent, kind: .question, text: try Self.message(question), at: Self.kept(now))
        guard comments[index].openQuestion == nil else { throw .questionOpen(id) }
        comments[index].thread.append(message)
        return message
    }

    /// The person's answer to a comment's open question, which closes it.
    @discardableResult
    public mutating func answer(_ id: ItemID, text: String, messageID: ItemID, at now: Date) throws(ReviewRefusal) -> ThreadMessage {
        guard let index = comments.firstIndex(where: { $0.id == id }) else { throw .unknownComment(id.text) }
        let message = ThreadMessage(id: messageID, author: .person, kind: .answer, text: try Self.message(text), at: Self.kept(now))
        guard comments[index].openQuestion != nil else { throw .noQuestion(id) }
        comments[index].thread.append(message)
        return message
    }

    /// A time as the review keeps it: to the millisecond, which is what
    /// its file holds, so a review reads back as it was.
    private static func kept(_ time: Date) -> Date {
        Date(timeIntervalSince1970: (time.timeIntervalSince1970 * 1000).rounded(.down) / 1000)
    }

    private func batchIndex(_ id: ItemID) throws(ReviewRefusal) -> Int {
        guard let index = batches.firstIndex(where: { $0.id == id }) else { throw .unknownBatch(id.text) }
        return index
    }

    /// A comment the listener can answer: one that was sent.
    private func sentIndex(_ id: ItemID) throws(ReviewRefusal) -> Int {
        guard let index = comments.firstIndex(where: { $0.id == id }) else { throw .unknownComment(id.text) }
        guard comments[index].batchID != nil else { throw .notSent(id) }
        return index
    }

    private static func message(_ text: String) throws(ReviewRefusal) -> String {
        let words = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty else { throw .emptyMessage }
        return words
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
