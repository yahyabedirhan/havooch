import Foundation

/// Why a change to a review is refused. A refused change leaves the review
/// as it was.
public enum ReviewRefusal: Error, Equatable, Sendable {
    /// A comment needs words.
    case emptyText
    /// The review has no comment with this id.
    case unknownComment(String)
    /// Only a queued comment can be edited or deleted.
    case notQueued(ItemID, CommentState)

    /// The refusal as the one line the command prints.
    public var line: String {
        switch self {
        case .emptyText:
            "a comment needs text"
        case .unknownComment(let id):
            "no comment `\(id)` on this video; `video-review state --json` lists the comments"
        case .notQueued(let id, let state):
            "\(id) is \(state.rawValue), and only a queued comment can change"
        }
    }
}
