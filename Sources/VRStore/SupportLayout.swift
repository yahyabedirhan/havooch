import Foundation
import VRReview

/// Every path under a support folder, in one place:
///
///     <root>/videos/<content hash>/frames/<comment id>.png
///
/// The root is the person's support folder, or a demo's.
public struct SupportLayout: Equatable, Sendable {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    /// One folder per video, named by its content hash.
    public var videosFolder: URL {
        root.appendingPathComponent("videos", isDirectory: true)
    }

    /// Everything kept for the video `hash` names.
    public func folder(_ hash: String) -> URL {
        videosFolder.appendingPathComponent(hash, isDirectory: true)
    }

    /// The keyframe of the comment `id` on the video `hash` names.
    public func keyframe(_ id: CommentID, of hash: String) -> URL {
        folder(hash).appendingPathComponent("frames", isDirectory: true).appendingPathComponent("\(id.rawValue).png")
    }
}
