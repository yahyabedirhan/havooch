import AppKit
import AVFoundation

@Observable
final class Thumbnails {
    struct Key: Hashable {
        var contentHash: String
        var position: Double
    }

    nonisolated static let maximumSize = CGSize(width: 640, height: 360)

    private var images: [Key: NSImage] = [:]
    @ObservationIgnored private var asked: Set<Key> = []

    static func key(of recent: StateReport.Recent) -> Key {
        Key(contentHash: recent.contentHash, position: recent.position)
    }

    func image(for recent: StateReport.Recent) -> NSImage? {
        images[Self.key(of: recent)]
    }

    func load(_ recent: StateReport.Recent) async {
        let key = Self.key(of: recent)
        guard recent.available, !asked.contains(key) else { return }
        asked.insert(key)
        guard let frame = await Self.frame(of: recent.url, at: RecentCard.thumbnailTime(position: recent.position)) else { return }
        images[key] = NSImage(cgImage: frame, size: NSSize(width: frame.width, height: frame.height))
    }

    static func key(of project: StateReport.HomeProject) -> Key {
        Key(contentHash: "project \(project.slug) \(project.latestPath ?? "")", position: 1)
    }

    func image(for project: StateReport.HomeProject) -> NSImage? {
        images[Self.key(of: project)]
    }

    func load(_ project: StateReport.HomeProject) async {
        let key = Self.key(of: project)
        guard project.available, let path = project.latestPath, !asked.contains(key) else { return }
        asked.insert(key)
        guard let frame = await Self.frame(of: URL(fileURLWithPath: path), at: 1) else { return }
        images[key] = NSImage(cgImage: frame, size: NSSize(width: frame.width, height: frame.height))
    }

    static func key(still path: String, at seconds: Double) -> Key {
        Key(contentHash: "still \(path)", position: (seconds * 10).rounded() / 10)
    }

    func still(of path: String, at seconds: Double) -> NSImage? {
        images[Self.key(still: path, at: seconds)]
    }

    func loadStill(of path: String, at seconds: Double) async {
        let key = Self.key(still: path, at: seconds)
        guard !asked.contains(key) else { return }
        asked.insert(key)
        guard let frame = await Self.frame(of: URL(fileURLWithPath: path), at: key.position) else { return }
        images[key] = NSImage(cgImage: frame, size: NSSize(width: frame.width, height: frame.height))
    }

    @concurrent
    nonisolated private static func frame(of url: URL, at seconds: Double) async -> CGImage? {
        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration).seconds, duration.isFinite else { return nil }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = maximumSize
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let inside = min(max(seconds, 0), max(duration - 0.05, 0))
        return try? await generator.image(at: CMTime(seconds: inside, preferredTimescale: 600)).image
    }
}
