import Foundation

/// One comment on a video: text at a time. Its keyframe is a file named
/// after its id, so the comment holds no path.
public struct Comment: Codable, Equatable, Sendable, Identifiable {
    public let id: ItemID
    /// The moment in the video, in seconds.
    public let time: TimeInterval
    public internal(set) var text: String
    public internal(set) var state: CommentState
}
