import Foundation
import ReviewTranscript

/// A video's transcribed speech, kept so a video is transcribed once, at
/// `SupportLayout.transcriptFile`.
public struct TranscriptFiles: Sendable {
    public let layout: SupportLayout

    public init(layout: SupportLayout) {
        self.layout = layout
    }

    /// The transcript kept for the video; nil when there's none, or the
    /// file doesn't read.
    public func load(_ contentHash: String) -> Transcript? {
        guard let data = try? Data(contentsOf: layout.transcriptFile(contentHash)) else { return nil }
        return try? JSONDecoder().decode(Transcript.self, from: data)
    }

    /// Keeps `transcript` for the video, replacing what's there. A
    /// transcript that can't be written is transcribed again next time.
    public func save(_ transcript: Transcript, contentHash: String) {
        let file = layout.transcriptFile(contentHash)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(transcript) else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }
}
