import AppKit
import AVFoundation

/// The recent videos' thumbnails: the frame at each one's saved position
/// (`RecentCard.thumbnailTime`), made with `AVAssetImageGenerator` when its
/// card first shows. Kept in memory for the run only, keyed by content hash
/// and position, so a video stopped elsewhere gets its new frame.
@Observable
final class Thumbnails {
    struct Key: Hashable {
        var contentHash: String
        var position: Double
    }

    /// The largest thumbnail made, in pixels: twice a wide card.
    nonisolated static let maximumSize = CGSize(width: 640, height: 360)

    private var images: [Key: NSImage] = [:]
    /// The keys being made or that failed, so a card that shows again
    /// does not ask twice.
    @ObservationIgnored private var asked: Set<Key> = []

    static func key(of recent: StateReport.Recent) -> Key {
        Key(contentHash: recent.contentHash, position: recent.position)
    }

    /// The thumbnail of `recent`; nil until it is made, and for a video
    /// that is not there.
    func image(for recent: StateReport.Recent) -> NSImage? {
        images[Self.key(of: recent)]
    }

    /// Makes the thumbnail of `recent` once. Nothing for a video that is
    /// not there or a frame that does not read.
    func load(_ recent: StateReport.Recent) async {
        let key = Self.key(of: recent)
        guard recent.available, !asked.contains(key) else { return }
        asked.insert(key)
        guard let frame = await Self.frame(of: recent.url, at: RecentCard.thumbnailTime(position: recent.position)) else { return }
        images[key] = NSImage(cgImage: frame, size: NSSize(width: frame.width, height: frame.height))
    }

    /// The frame of the video at `url` at `seconds`, inside its duration,
    /// at most `maximumSize`, off the main actor.
    @concurrent
    nonisolated private static func frame(of url: URL, at seconds: Double) async -> CGImage? {
        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration).seconds, duration.isFinite else { return nil }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = maximumSize
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        // The video's end is past its last frame: ask a little before it.
        let inside = min(max(seconds, 0), max(duration - 0.05, 0))
        return try? await generator.image(at: CMTime(seconds: inside, preferredTimescale: 600)).image
    }
}
