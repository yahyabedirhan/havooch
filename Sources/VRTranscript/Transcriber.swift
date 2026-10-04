import Foundation

/// Where a video's transcript stands: which source it comes from, whether
/// that source has every line, how many it has so far, and why it has no
/// more when it stopped short.
public struct TranscriptStatus: Equatable, Sendable {
    /// `voiceover`, `subtitles` or `speech`; nil when no source has the video.
    public var source: String?
    public var complete: Bool
    public var lines: Int
    /// Why the source stopped before it had every line, in words.
    public var problem: String?

    public init(source: String? = nil, complete: Bool = false, lines: Int = 0, problem: String? = nil) {
        self.source = source
        self.complete = complete
        self.lines = lines
        self.problem = problem
    }
}

/// The one interface the app knows: the timed lines of a video, as far as
/// they exist. What is behind it (which sources, in which order) can be
/// replaced without the app noticing.
public protocol Transcriber: Sendable {
    /// A video was opened: starts what takes time, and returns without
    /// waiting for it.
    func prepare(_ video: URL) async
    /// The lines that overlap `window`, in time order, as they exist now.
    /// Never waits for a transcription that still runs.
    func lines(for video: URL, in window: ClosedRange<TimeInterval>) async -> [TimedLine]
    func status(for video: URL) async -> TranscriptStatus
}
