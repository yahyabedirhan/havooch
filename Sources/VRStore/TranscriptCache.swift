import Foundation
import VRTranscript

/// The finished speech transcript of each video, in `transcript.json` in
/// the video's folder: what `SpeechSource` reads and writes. The video is
/// named by its content hash, so a renamed or moved copy finds its
/// transcript.
public struct TranscriptCache: TranscriptCaching {
    private struct File: StoredFile {
        static let current = 1
        var version = File.current
        var lines: [TimedLine]
    }

    private let layout: SupportLayout

    public init(layout: SupportLayout) {
        self.layout = layout
    }

    /// The lines kept for `video`. A file that doesn't read, or that a
    /// newer build wrote, is moved aside and counts as none.
    public func load(for video: URL) -> [TimedLine]? {
        file(for: video).flatMap { File.read(at: $0) }?.lines
    }

    /// Keeps `lines` for `video`. A transcript that can't be written is
    /// recognised again at the next open.
    public func save(_ lines: [TimedLine], for video: URL) {
        guard let file = file(for: video) else { return }
        try? File(lines: lines).write(to: file)
    }

    private func file(for video: URL) -> URL? {
        (try? ContentHash.of(video)).map(layout.transcriptFile)
    }
}
