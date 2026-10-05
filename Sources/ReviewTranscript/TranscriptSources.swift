import Foundation

/// The sources in the order they're asked: the first one that has
/// something for the video serves it. It is a `Transcriber` itself, so the
/// app holds one thing and asks it.
public struct TranscriptSources: Transcriber {
    public let sources: [any Transcriber]

    public init(_ sources: [any Transcriber]) {
        self.sources = sources
    }

    /// The spec's order: `voiceover.json`, then a `.srt` or `.vtt` sidecar,
    /// then `speech`, which serves every video.
    public static func standard(speech: any Transcriber) -> TranscriptSources {
        TranscriptSources([VoiceoverSource(), SubtitleSource(), speech])
    }

    /// The first source that serves `video`, with what it has now.
    public func pick(for video: VideoFile) -> (source: any Transcriber, transcript: Transcript)? {
        for source in sources {
            if let transcript = source.transcript(of: video) { return (source, transcript) }
        }
        return nil
    }

    public func transcript(of video: VideoFile) -> Transcript? {
        pick(for: video)?.transcript
    }

    /// Only the source that serves the video starts its work: a video with
    /// a sidecar is never transcribed from its sound.
    public func prepare(_ video: VideoFile) {
        pick(for: video)?.source.prepare(video)
    }
}
