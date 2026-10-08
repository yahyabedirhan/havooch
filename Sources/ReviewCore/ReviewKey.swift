import Foundation

/// Which review something belongs to: a plain video's, by its content
/// hash. A listener listens to one review, and each review keeps its own
/// outbox. A project's review becomes a second case when projects come
/// (`.project(slug)`), with no change to the listeners.
public enum ReviewKey: Hashable, Sendable {
    case video(contentHash: String)

    /// The name its files go by: `video-<content hash>`.
    public var fileName: String {
        switch self {
        case .video(let contentHash): "video-\(contentHash)"
        }
    }

    /// Whether the send `ref` is one of this review's.
    public func holds(_ ref: SendRef) -> Bool {
        covers(ref.contentHash)
    }

    /// Whether the video with `contentHash` is this review's: its context
    /// goes to this review's listener.
    public func covers(_ contentHash: String) -> Bool {
        switch self {
        case .video(let own): own == contentHash
        }
    }
}
