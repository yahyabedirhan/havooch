/// Why a review refuses a change. `message` is the one line a command
/// prints on standard error.
public enum ReviewError: Error, Equatable, Sendable {
    case emptyText
    case timeOutsideVideo(Double, duration: Double)
    case regionOutsideFrame
    case unknownComment(String)
    case unknownBatch(String)
    case notQueued(CommentID, CommentState)
    case emptyQueue
    case emptyMessage
    case notSent(CommentID, CommentState)
    case noOpenQuestion(CommentID)
    case illegalMove(CommentID, from: CommentState, to: CommentState)

    public var message: String {
        switch self {
        case .emptyText:
            "a comment needs some text"
        case .timeOutsideVideo(let seconds, let duration):
            "\(seconds) s is outside the video, which ends at \(duration) s"
        case .regionOutsideFrame:
            "a region must lie inside the frame: x, y, w and h are parts of it from 0 to 1, "
                + "w and h above 0, x + w and y + h at most 1"
        case .unknownComment(let id):
            "there is no comment `\(id)`"
        case .unknownBatch(let id):
            "there is no batch `\(id)`"
        case .emptyQueue:
            "the queue is empty: there is no comment to send"
        case .notQueued(let id, let state):
            "\(id.rawValue) is \(state.rawValue); only a queued comment can be edited or deleted"
        case .emptyMessage:
            "a message needs some text"
        case .notSent(let id, let state):
            "\(id.rawValue) is \(state.rawValue); a listener answers a comment only once it was sent"
        case .noOpenQuestion(let id):
            "\(id.rawValue) has no question waiting for an answer"
        case .illegalMove(let id, let from, let to):
            "\(id.rawValue) is \(from.rawValue) and can't become \(to.rawValue); a comment only moves forward: "
                + "sent, acknowledged, working, then done or failed, which are final"
        }
    }
}
