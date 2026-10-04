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
    /// A region is inside the frame and has an area.
    case badRegion(x: Double, y: Double, w: Double, h: Double)
    /// A batch needs at least one queued comment.
    case nothingQueued
    /// The review has no batch with this id.
    case unknownBatch(String)
    /// A thread message needs words.
    case emptyMessage
    /// The listener answers only a comment that was sent to it.
    case notSent(ItemID)
    /// A comment's state only moves forward, and `done` and `failed` are
    /// final.
    case illegalMove(ItemID, from: CommentState, to: CommentState)
    /// A comment has one open question at most.
    case questionOpen(ItemID)
    /// An answer needs an open question.
    case noQuestion(ItemID)

    /// The refusal as the one line the command prints.
    public var line: String {
        switch self {
        case .emptyText:
            "a comment needs text"
        case .unknownComment(let id):
            "no comment `\(id)` on this video; `video-review state --json` lists the comments"
        case .notQueued(let id, let state):
            "\(id) is \(state.rawValue), and only a queued comment can change"
        case .badRegion(let x, let y, let w, let h):
            "the region \(x),\(y),\(w),\(h) isn't a rectangle inside the frame; give x,y,w,h from 0 to 1 from the top-left corner, with a width and a height above 0, x+w at most 1 and y+h at most 1"
        case .nothingQueued:
            "no comment is queued, so there's nothing to send; queue one with `video-review comment add <text>`"
        case .unknownBatch(let id):
            "no batch `\(id)`; `video-review state --json` lists the batches"
        case .emptyMessage:
            "a message needs text"
        case .notSent(let id):
            "\(id) is queued and wasn't sent yet, so there's nothing to answer"
        case .illegalMove(let id, let from, let to):
            "\(id) is \(from.rawValue) and can't move to \(to.rawValue): a comment only moves forward (sent, acknowledged, working, then done or failed)"
        case .questionOpen(let id):
            "\(id) already has an open question; its answer comes in the comment's thread, which `video-review state --json` shows"
        case .noQuestion(let id):
            "\(id) has no open question to answer"
        }
    }
}
