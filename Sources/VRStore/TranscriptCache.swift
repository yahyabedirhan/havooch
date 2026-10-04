import Foundation
import VRTranscript

/// A video's speech transcript on disk, so a video is transcribed once:
///
///     videos/<contentHash>/transcript.json   the lines, in time order
///
/// Only speech is kept: a sidecar is read again each time its video opens.
public struct TranscriptCache: Sendable {
    /// The support folder.
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    /// The lines kept for the video `hash`, or nil when there are none, or
    /// the file can't be read.
    public func load(_ hash: String) -> [TranscriptLine]? {
        (try? JSONFile.read([TranscriptLine].self, at: file(hash))) ?? nil
    }

    public func save(_ lines: [TranscriptLine], for hash: String) throws {
        try JSONFile.write(lines, to: file(hash))
    }

    private func file(_ hash: String) -> URL {
        root
            .appendingPathComponent("videos", isDirectory: true)
            .appendingPathComponent(hash, isDirectory: true)
            .appendingPathComponent("transcript.json")
    }
}
