import Foundation
import ReviewCore

nonisolated enum WindowTarget: Codable, Hashable, Sendable {
    case video(contentHash: String, path: String)
    case project(slug: String)

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
