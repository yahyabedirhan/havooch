/// Why a review refuses a change. `message` is the one line a command
/// prints on standard error.
public enum ReviewError: Error, Equatable, Sendable {
    case emptyText
    case timeOutsideVideo(Double, duration: Double)
    case unknownComment(String)
    case notQueued(CommentID, CommentState)

    public var message: String {
        switch self {
        case .emptyText:
            "a comment needs some text"
        case .timeOutsideVideo(let seconds, let duration):
            "\(seconds) s is outside the video, which ends at \(duration) s"
        case .unknownComment(let id):
            "the open video has no comment `\(id)`"
        case .notQueued(let id, let state):
            "\(id.rawValue) is \(state.rawValue); only a queued comment can be edited or deleted"
        }
    }
}
