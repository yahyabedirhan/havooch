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
            "the open video has no comment `\(id)`"
        case .unknownBatch(let id):
            "there is no batch `\(id)`"
        case .emptyQueue:
            "the queue is empty: there is no comment to send"
        case .notQueued(let id, let state):
            "\(id.rawValue) is \(state.rawValue); only a queued comment can be edited or deleted"
        }
    }
}
