/// Where a comment is on its way from the person to the agent's answer. A
/// comment moves only forward, except for a requeue: a batch a listener took
/// and didn't finish goes back to `sent` for the next listener.
///
///     draft → queued → sent → acknowledged → working → done | failed
public enum CommentState: String, Codable, Equatable, Sendable, CaseIterable {
    /// Being written: it has its time and its frame, not yet its text.
    case draft
    /// Written, waiting in the queue to be sent.
    case queued
    case sent
    case acknowledged
    case working
    case done
    case failed

    /// `done` and `failed` end a comment: nothing moves it again.
    public var isFinal: Bool {
        self == .done || self == .failed
    }

    /// Whether a comment in this state may move to `next`. A listener's
    /// status (`working`, `done`, `failed`) may skip forward from any sent
    /// state; `acknowledged` and `working` may go back to `sent`, the
    /// requeue.
    public func canMove(to next: CommentState) -> Bool {
        switch (self, next) {
        case (.draft, .queued), (.queued, .sent), (.sent, .acknowledged):
            true
        case (.sent, .working), (.sent, .done), (.sent, .failed),
             (.acknowledged, .working), (.acknowledged, .done), (.acknowledged, .failed),
             (.working, .done), (.working, .failed):
            true
        case (.acknowledged, .sent), (.working, .sent):
            true
        default:
            false
        }
    }
}

/// One piece of feedback: a time in the video, what the person wrote about
/// it, and where it is on its way. Its keyframe is a file the store names by
/// the comment's id.
public struct Comment: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    /// In seconds, to the millisecond.
    public var time: Double
    public var text: String
    public var state: CommentState

    public init(id: String, time: Double, text: String = "", state: CommentState = .draft) {
        self.id = id
        self.time = time
        self.text = text
        self.state = state
    }
}
