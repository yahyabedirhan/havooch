import Foundation

/// The video a transcript is asked for.
public struct VideoFile: Equatable, Sendable {
    public var url: URL
    /// The hash of the file's content: what a source keeps its work under.
    public var contentHash: String
    /// Frames a second, which turn a scene's length into its frames.
    public var frameRate: Double
    public var duration: TimeInterval

    public init(url: URL, contentHash: String, frameRate: Double, duration: TimeInterval) {
        self.url = url
        self.contentHash = contentHash
        self.frameRate = frameRate
        self.duration = duration
    }
}

/// Where a transcript comes from, in the order the sources are asked.
public enum TranscriptSource: String, Codable, Sendable {
    /// The explainer studio's `voiceover.json`.
    case voiceover
    /// A `.srt` or `.vtt` sidecar.
    case subtitles
    /// On-device transcription of the video's sound.
    case speech
}

/// What's known of one video's transcript now.
public struct Transcript: Codable, Equatable, Sendable {
    public var source: TranscriptSource
    /// The lines so far, in time order.
    public var lines: [TranscriptLine]
    /// False while the source still works, and when it gave up.
    public var complete: Bool
    /// Why the source gave up; nil while it works and when it's done.
    public var problem: String?

    public init(source: TranscriptSource, lines: [TranscriptLine], complete: Bool, problem: String? = nil) {
        self.source = source
        self.lines = lines
        self.complete = complete
        self.problem = problem
    }
}

/// A source of transcripts: give it a video and a time window, it returns
/// the timed lines. The one interface the app reads transcripts through, so
/// a better source can replace these later.
///
/// A source answers at once with what it has. One that works in the
/// background (speech) never makes its caller wait for the rest: a comment
/// sent before the transcript is ready gets the lines that exist then.
public protocol Transcriber: Sendable {
    /// What this source has of `video`'s transcript now; nil when it has
    /// nothing to say about this video (no sidecar), so the next source is
    /// asked.
    func transcript(of video: VideoFile) -> Transcript?

    /// The video opened: a source that needs time starts its work.
    func prepare(_ video: VideoFile)

    /// The lines of `video` that overlap `window`, each kept whole.
    func lines(for video: VideoFile, in window: ClosedRange<TimeInterval>) -> [TranscriptLine]
}

extension Transcriber {
    public func prepare(_ video: VideoFile) {}

    public func lines(for video: VideoFile, in window: ClosedRange<TimeInterval>) -> [TranscriptLine] {
        TranscriptWindow.cut(transcript(of: video)?.lines ?? [], to: window)
    }
}
