import Foundation

/// Where a comment is on its way from the person to the agent and back:
/// `draft → queued → sent → acknowledged → working → done | failed`.
///
/// A draft is a comment still in the comment box; it enters a review as
/// `queued`.
public enum CommentState: String, Codable, Sendable, CaseIterable {
    case draft, queued, sent, acknowledged, working, done, failed

    /// Whether a comment in this state may move to `next`: forward only. A
    /// state may be skipped (`sent → working`), and `done` and `failed` are
    /// final.
    public func canMove(to next: CommentState) -> Bool {
        guard !isFinal, next != self else { return false }
        return next.isFinal || next.step > step
    }

    /// Whether the comment is finished: `done` or `failed`.
    public var isFinal: Bool {
        self == .done || self == .failed
    }

    /// Whether the person can still change or delete the comment: only
    /// while it's queued. A sent comment is a record.
    public var isEditable: Bool {
        self == .queued
    }

    /// The state's place on the way; `done` and `failed` share the end.
    private var step: Int {
        switch self {
        case .draft: 0
        case .queued: 1
        case .sent: 2
        case .acknowledged: 3
        case .working: 4
        case .done, .failed: 5
        }
    }
}
