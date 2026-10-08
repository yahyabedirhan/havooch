import Foundation

/// What a window holds: one plain video (ADR 0003). It is the value of the
/// window's scene (`WindowGroup(for:)`); a window that holds nothing has
/// none and shows the home screen. Two targets are the same when their
/// video's content is: a renamed or moved copy is the same video, so no
/// two windows ever hold it.
nonisolated enum WindowTarget: Codable, Hashable, Sendable {
    /// A plain video: the hash of its content, and its file where it was opened.
    case video(contentHash: String, path: String)

    /// The content hash of the target's video.
    var contentHash: String {
        switch self {
        case .video(let contentHash, _): contentHash
        }
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.contentHash == rhs.contentHash
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(contentHash)
    }
}
