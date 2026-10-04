import Foundation
import VRReview

/// Every path under a support folder, in one place:
///
///     <root>/app.json
///     <root>/listener.json
///     <root>/videos/<content hash>/review.json
///     <root>/videos/<content hash>/frames/<comment id>.png
///     <root>/videos/<content hash>/crops/<comment id>.png
///     <root>/videos/<content hash>/transcript.json
///
/// The root is the person's support folder, or a demo's.
public struct SupportLayout: Equatable, Sendable {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    /// What the app remembers about itself: the last video.
    public var appFile: URL {
        root.appendingPathComponent("app.json")
    }

    /// The listener session and the batches on their way.
    public var listenerFile: URL {
        root.appendingPathComponent("listener.json")
    }

    /// One folder per video, named by its content hash.
    public var videosFolder: URL {
        root.appendingPathComponent("videos", isDirectory: true)
    }

    /// Everything kept for the video `hash` names.
    public func folder(_ hash: String) -> URL {
        videosFolder.appendingPathComponent(hash, isDirectory: true)
    }

    /// The review of the video `hash` names: its comments with their
    /// threads, its batches, its note and its id counters.
    public func reviewFile(_ hash: String) -> URL {
        folder(hash).appendingPathComponent("review.json")
    }

    /// The keyframe of the comment `id` on the video `hash` names.
    public func keyframe(_ id: CommentID, of hash: String) -> URL {
        folder(hash).appendingPathComponent("frames", isDirectory: true).appendingPathComponent("\(id.rawValue).png")
    }

    /// The crop of the comment `id` on the video `hash` names: the part of
    /// its keyframe its region points at.
    public func crop(_ id: CommentID, of hash: String) -> URL {
        folder(hash).appendingPathComponent("crops", isDirectory: true).appendingPathComponent("\(id.rawValue).png")
    }

    /// The speech transcript of the video `hash` names, once it finished.
    public func transcriptFile(_ hash: String) -> URL {
        folder(hash).appendingPathComponent("transcript.json")
    }
}
