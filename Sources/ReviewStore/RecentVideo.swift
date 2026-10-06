import Foundation

/// One video on the recent videos: where it was last opened, its content,
/// when, and where the person left the playhead.
public struct RecentVideo: Codable, Equatable, Sendable {
    /// The absolute path the video was last opened at.
    public var path: String
    /// The hash of the file's content: the video's identity, so a renamed
    /// or moved copy is the same entry.
    public var contentHash: String
    /// When the person last opened it.
    public var openedAt: Date
    /// The playhead's last position, in seconds.
    public var position: Double

    public init(path: String, contentHash: String, openedAt: Date, position: Double) {
        self.path = path
        self.contentHash = contentHash
        self.openedAt = openedAt
        self.position = position
    }
}
