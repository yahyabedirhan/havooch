import Foundation

/// Where a comment stands, from being typed to being finished. A comment
/// only moves forward; `done` and `failed` are final.
public enum CommentState: String, Codable, Sendable, CaseIterable {
    case draft, queued, sent, acknowledged, working, done, failed

    /// Whether a comment in this state may move to `next`:
    ///
    ///     draft → queued → sent → acknowledged → working → done | failed
    ///
    /// with the steps a listener may skip: `sent` straight to `working`,
    /// and `sent` or `acknowledged` straight to `done` or `failed`.
    public func canMove(to next: CommentState) -> Bool {
        switch (self, next) {
        case (.draft, .queued), (.queued, .sent), (.sent, .acknowledged): true
        case (.sent, .working), (.acknowledged, .working): true
        case (.sent, .done), (.acknowledged, .done), (.working, .done): true
        case (.sent, .failed), (.acknowledged, .failed), (.working, .failed): true
        default: false
        }
    }
}

/// One piece of feedback at a time in the video.
public struct Comment: Codable, Equatable, Identifiable, Sendable {
    public var id: CommentID
    /// The time in the video it's about, in seconds.
    public var time: Double
    public var text: String
    public var state: CommentState
    /// The batch it was sent in, once it was.
    public var batch: BatchID?
    public var thread: [ThreadMessage]
    public var createdAt: Date

    public init(
        id: CommentID, time: Double, text: String, state: CommentState,
        batch: BatchID? = nil, thread: [ThreadMessage] = [], createdAt: Date
    ) {
        self.id = id
        self.time = time
        self.text = text
        self.state = state
        self.batch = batch
        self.thread = thread
        self.createdAt = createdAt
    }
}
