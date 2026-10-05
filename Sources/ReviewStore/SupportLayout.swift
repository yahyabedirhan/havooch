import Foundation
import ReviewCore

/// Every path the store keeps under one support folder: the person's own,
/// or a demo's. The one place that names a file; `Library`, the image and
/// transcript files and the payload all ask it. It never looks outside its
/// root, so demo data and real data can't mix. A pure value: it touches no
/// file.
///
///     <root>/outbox.json                              the batches in line for the listener
///     <root>/recent.json                              the path of the last open video
///     <root>/settings.json                            the pinned theme, token overrides, sidebar width
///     <root>/Themes/<any name>.json                   the person's own themes
///     <root>/videos/<contentHash>/review.json         one video's review
///     <root>/videos/<contentHash>/transcript.json     its transcribed speech
///     <root>/videos/<contentHash>/frames/<id>.png     a comment's keyframe
///     <root>/videos/<contentHash>/crops/<id>.png      a region comment's crop
///
/// A video's folder is named after the hash of its content, so a renamed or
/// moved file finds its review again. The socket and the demo pointer are
/// `ReviewWire`'s: the command needs them and doesn't link the store.
public struct SupportLayout: Equatable, Sendable {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    public var outboxFile: URL { root.appendingPathComponent("outbox.json") }
    public var recentFile: URL { root.appendingPathComponent("recent.json") }
    public var settingsFile: URL { root.appendingPathComponent("settings.json") }
    public var themesFolder: URL { root.appendingPathComponent("Themes", isDirectory: true) }
    public var videosFolder: URL { root.appendingPathComponent("videos", isDirectory: true) }

    /// The folder of everything kept about the video with `contentHash`.
    public func folder(_ contentHash: String) -> URL {
        videosFolder.appendingPathComponent(contentHash, isDirectory: true)
    }

    /// The review file of the video with `contentHash`.
    public func reviewFile(_ contentHash: String) -> URL {
        folder(contentHash).appendingPathComponent("review.json")
    }

    /// The transcribed speech of the video with `contentHash`.
    public func transcriptFile(_ contentHash: String) -> URL {
        folder(contentHash).appendingPathComponent("transcript.json")
    }

    /// The keyframe of `item` on the video with `contentHash`.
    public func keyframe(_ item: ItemID, of contentHash: String) -> URL {
        folder(contentHash).appendingPathComponent("frames", isDirectory: true).appendingPathComponent("\(item.text).png")
    }

    /// The crop of `item`'s region on the video with `contentHash`. Only an
    /// item on a region has the file.
    public func crop(_ item: ItemID, of contentHash: String) -> URL {
        folder(contentHash).appendingPathComponent("crops", isDirectory: true).appendingPathComponent("\(item.text).png")
    }
}
