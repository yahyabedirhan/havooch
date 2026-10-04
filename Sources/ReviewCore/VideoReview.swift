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

    public init(video: VideoInfo) {
        self.video = video
        comments = []
    }

    /// The comments waiting to be sent, in time order.
    public var queue: [Comment] {
        comments.filter { $0.state == .queued }
    }

    public func comment(_ id: ItemID) -> Comment? {
        comments.first { $0.id == id }
    }

    /// Queues a comment at `time`. The text loses the space around it; a
    /// text with no words is refused.
    @discardableResult
    public mutating func addComment(id: ItemID, time: TimeInterval, text: String) throws(ReviewRefusal) -> Comment {
        let comment = Comment(id: id, time: time, text: try Self.words(text), state: .queued)
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
