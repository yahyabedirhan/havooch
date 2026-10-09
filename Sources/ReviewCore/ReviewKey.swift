import Foundation

/// Which review something belongs to: a plain video's, by its
/// content hash, or a project's, by its slug. A listener listens to one
/// review, and each review keeps its own outbox.
public enum ReviewKey: Hashable, Sendable {
    case video(contentHash: String)
    case project(slug: String)

    /// The name its files go by: `video-<content hash>` or `project-<slug>`.
    public var fileName: String {
        switch self {
        case .video(let contentHash): "video-\(contentHash)"
        case .project(let slug): "project-\(slug)"
        }
    }

    /// The content hash of a plain video's review; nil for a project's.
    public var contentHash: String? {
        switch self {
        case .video(let contentHash): contentHash
        case .project: nil
        }
    }

    /// The slug of a project's review; nil for a plain video's.
    public var slug: String? {
        switch self {
        case .video: nil
        case .project(let slug): slug
        }
    }

    /// The name a listener session's context is kept under
    /// (`Outbox.contextSent`): a plain video's content hash, as builds
    /// before projects kept it, or `project-<slug>`.
    public var contextKey: String {
        switch self {
        case .video(let contentHash): contentHash
        case .project: fileName
        }
    }

    /// Whether the send `ref` is one of this review's.
    public func holds(_ ref: SendRef) -> Bool {
        ref.review == self
    }

    /// Whether the context kept under `contextKey` is this review's.
    public func covers(_ contextKey: String) -> Bool {
        self.contextKey == contextKey
    }
}
