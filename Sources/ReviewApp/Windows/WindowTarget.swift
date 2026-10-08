import Foundation
import ReviewCore

/// What a window holds: one plain video, or one project (ADR 0003). It is
/// the value of the window's scene (`WindowGroup(for:)`); a window that
/// holds nothing has none and shows the home screen. Two targets are the
/// same when their review is: a plain video by its content, so a renamed
/// or moved copy is the same video, and a project by its slug, whichever
/// version is on screen. No two windows ever hold the same one.
nonisolated enum WindowTarget: Codable, Hashable, Sendable {
    /// A plain video: the hash of its content, and its file where it was opened.
    case video(contentHash: String, path: String)
    /// A project (ADR 0004), by its slug.
    case project(slug: String)

    /// The review the target opens on.
    var reviewKey: ReviewKey {
        switch self {
        case .video(let contentHash, _): .video(contentHash: contentHash)
        case .project(let slug): .project(slug: slug)
        }
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.reviewKey == rhs.reviewKey
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(reviewKey)
    }
}
