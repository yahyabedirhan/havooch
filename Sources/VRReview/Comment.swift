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
    /// The part of the frame it points at; nil when it's about the whole frame.
    public var region: Region?
    public var state: CommentState
    /// The batch it was sent in, once it was.
    public var batch: BatchID?
    public var thread: [ThreadMessage]
    public var createdAt: Date

    public init(
        id: CommentID, time: Double, text: String, region: Region? = nil, state: CommentState,
        batch: BatchID? = nil, thread: [ThreadMessage] = [], createdAt: Date
    ) {
        self.id = id
        self.time = time
        self.text = text
        self.region = region
        self.state = state
        self.batch = batch
        self.thread = thread
        self.createdAt = createdAt
    }

    /// The agent's latest question in the thread, answered or not.
    public var lastQuestion: ThreadMessage? {
        thread.last { $0.kind == .question }
    }

    /// The person's answer to the latest question, once there is one.
    public var lastAnswer: ThreadMessage? {
        guard let asked = thread.lastIndex(where: { $0.kind == .question }) else { return nil }
        return thread[asked...].first { $0.kind == .answer }
    }

    /// The question that waits for the person: the latest one, while
    /// nothing answers it.
    public var openQuestion: ThreadMessage? {
        lastAnswer == nil ? lastQuestion : nil
    }
}
