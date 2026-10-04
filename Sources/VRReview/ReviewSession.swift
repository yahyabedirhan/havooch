import Foundation

/// Why a review won't do what was asked, as one line.
public struct ReviewRefusal: Error, Equatable, Sendable {
    public var reason: String

    public init(_ reason: String) {
        self.reason = reason
    }
}

/// One video's review: its comments and the batches they were sent in, and
/// every change to them. The rules
/// about a comment's state live here, so the window and the command line
/// are refused the same things in the same words.
public struct ReviewSession: Codable, Equatable, Sendable {
    public var video: VideoInfo
    /// Every comment of the video, drafts included, in time order; comments
    /// at the same time keep the order they were made in.
    public private(set) var comments: [Comment] = []
    /// The batches sent from this video, oldest first.
    public private(set) var batches: [Batch] = []

    public init(video: VideoInfo) {
        self.video = video
    }

    /// A review kept before anything was sent has no batches.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        video = try container.decode(VideoInfo.self, forKey: .video)
        comments = try container.decode([Comment].self, forKey: .comments)
        batches = try container.decodeIfPresent([Batch].self, forKey: .batches) ?? []
    }

    /// The comments waiting to be sent, in time order.
    public var queue: [Comment] {
        comments.filter { $0.state == .queued }
    }

    public func comment(_ id: String) -> Comment? {
        comments.first { $0.id == id }
    }

    public func batch(_ id: String) -> Batch? {
        batches.first { $0.id == id }
    }

    /// Whether every comment of the batch `batchID` is done or failed.
    public func isFinished(_ batchID: String) -> Bool {
        comments.filter { $0.batchID == batchID }.allSatisfy(\.state.isFinal)
    }

    // MARK: - Changes

    /// Starts a comment at `time`, on `region` of the frame when one was
    /// drawn: a draft, with no text yet.
    @discardableResult
    public mutating func draft(id: String, time: Double, region: Region? = nil) -> Comment {
        let comment = Comment(id: id, time: time, region: region)
        let index = comments.firstIndex { $0.time > time } ?? comments.endIndex
        comments.insert(comment, at: index)
        return comment
    }

    /// Gives a draft its text and puts it in the queue.
    public mutating func commit(_ id: String, text: String) throws(ReviewRefusal) {
        let index = try index(of: id)
        guard comments[index].state.canMove(to: .queued) else {
            throw ReviewRefusal("\(id) isn't a draft; it's \(comments[index].state.rawValue)")
        }
        comments[index].text = try Self.written(text)
        comments[index].state = .queued
    }

    /// Drops a draft that was never queued.
    public mutating func discard(_ id: String) throws(ReviewRefusal) {
        let index = try index(of: id)
        guard comments[index].state == .draft else {
            throw ReviewRefusal("\(id) isn't a draft; it's \(comments[index].state.rawValue)")
        }
        comments.remove(at: index)
    }

    /// Replaces a queued comment's text. A comment that was sent stays as
    /// the agent got it.
    public mutating func edit(_ id: String, text: String) throws(ReviewRefusal) {
        let index = try queued(id, toBe: "edited")
        comments[index].text = try Self.written(text)
    }

    /// Takes a queued comment out of the review.
    public mutating func delete(_ id: String) throws(ReviewRefusal) {
        comments.remove(at: try queued(id, toBe: "deleted"))
    }

    /// Sends every queued comment as one batch: each is `sent`, and names
    /// the batch. Refused with nothing queued.
    public mutating func send(batchID: String, at now: Date) throws(ReviewRefusal) -> Batch {
        let ids = queue.map(\.id)
        guard !ids.isEmpty else {
            throw ReviewRefusal("there's nothing to send: no comment is queued")
        }
        for index in comments.indices where comments[index].state == .queued {
            comments[index].state = .sent
            comments[index].batchID = batchID
        }
        let batch = Batch(id: batchID, sentAt: now, commentIDs: ids)
        batches.append(batch)
        return batch
    }

    /// The batch goes to another listener: its comments a listener had
    /// acknowledged or started go back to `sent`, the one move backward.
    /// Those done or failed stay.
    public mutating func requeue(_ batchID: String) {
        for index in comments.indices where comments[index].batchID == batchID {
            let state = comments[index].state
            if state != .sent, state.canMove(to: .sent) { comments[index].state = .sent }
        }
    }

    // MARK: - Rules

    /// A comment's text as it's kept: without the space around it, and not
    /// empty.
    public static func written(_ text: String) throws(ReviewRefusal) -> String {
        let kept = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !kept.isEmpty else { throw ReviewRefusal("a comment needs its text") }
        return kept
    }

    private func index(of id: String) throws(ReviewRefusal) -> Int {
        guard let index = comments.firstIndex(where: { $0.id == id }) else {
            throw ReviewRefusal("there's no comment \(id)")
        }
        return index
    }

    /// The place of the queued comment `id`; refused for a draft, and for a
    /// comment that was sent.
    private func queued(_ id: String, toBe change: String) throws(ReviewRefusal) -> Int {
        let index = try index(of: id)
        switch comments[index].state {
        case .queued:
            return index
        case .draft:
            throw ReviewRefusal("\(id) is still being written; it can't be \(change)")
        case .sent, .acknowledged, .working, .done, .failed:
            throw ReviewRefusal("\(id) was sent; it can't be \(change)")
        }
    }
}
