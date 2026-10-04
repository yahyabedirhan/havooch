import Foundation
import ReviewTranscript

/// Where a video's transcribed speech is kept, so a video is transcribed
/// once:
///
///     <support>/videos/<contentHash>/transcript.json
public struct TranscriptFiles: Sendable {
    public let support: URL

    public init(support: URL) {
        self.support = support
    }

    /// The transcript file of the video with `contentHash`.
    public func file(of contentHash: String) -> URL {
        support.appendingPathComponent("videos", isDirectory: true)
            .appendingPathComponent(contentHash, isDirectory: true)
            .appendingPathComponent("transcript.json")
    }

    /// The transcript kept for the video; nil when there's none, or the
    /// file doesn't read.
    public func load(_ contentHash: String) -> Transcript? {
        guard let data = try? Data(contentsOf: file(of: contentHash)) else { return nil }
        return try? JSONDecoder().decode(Transcript.self, from: data)
    }

    /// Keeps `transcript` for the video, replacing what's there. A
    /// transcript that can't be written is transcribed again next time.
    public func save(_ transcript: Transcript, contentHash: String) {
        let file = file(of: contentHash)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(transcript) else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }
}
