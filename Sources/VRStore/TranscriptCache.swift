import Foundation
import VRTranscript

/// The finished speech transcript of each video, in `transcript.json` in
/// the video's folder: what `SpeechSource` reads and writes. The video is
/// named by its content hash, so a renamed or moved copy finds its
/// transcript.
public struct TranscriptCache: TranscriptCaching {
    static let version = 1

    private struct File: Codable {
        var version: Int
        var lines: [TimedLine]
    }

    private let layout: SupportLayout

    public init(layout: SupportLayout) {
        self.layout = layout
    }

    /// The lines kept for `video`. A file that doesn't read, or that a
    /// newer build wrote, is moved aside and counts as none.
    public func load(for video: URL) -> [TimedLine]? {
        guard let file = file(for: video), let data = try? Data(contentsOf: file) else { return nil }
        guard let kept = try? JSONDecoder().decode(File.self, from: data), kept.version == Self.version else {
            let aside = file.deletingPathExtension().appendingPathExtension("unreadable.json")
            try? FileManager.default.removeItem(at: aside)
            try? FileManager.default.moveItem(at: file, to: aside)
            return nil
        }
        return kept.lines
    }

    /// Keeps `lines` for `video`. A transcript that can't be written is
    /// recognised again at the next open.
    public func save(_ lines: [TimedLine], for video: URL) {
        guard let file = file(for: video) else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(File(version: Self.version, lines: lines)) else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }

    private func file(for video: URL) -> URL? {
        (try? ContentHash.of(video)).map(layout.transcriptFile)
    }
}
