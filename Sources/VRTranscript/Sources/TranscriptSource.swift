import Foundation

/// What one source has for a video so far.
public struct SourceTranscript: Equatable, Sendable {
    public var lines: [TimedLine]
    /// Whether these are all the lines the source will ever have.
    public var complete: Bool
    /// Why the source stopped before it had every line, in words.
    public var problem: String?

    public init(lines: [TimedLine], complete: Bool = true, problem: String? = nil) {
        self.lines = lines
        self.complete = complete
        self.problem = problem
    }
}

/// One place a transcript comes from.
public protocol TranscriptSource: Sendable {
    /// The source's name in `state`: `voiceover`, `subtitles` or `speech`.
    var name: String { get }
    /// A video was opened and no earlier source has it: starts what takes
    /// time, and returns without waiting for it.
    func prepare(_ video: URL) async
    /// What the source has for `video` now; nil when it has nothing to do
    /// with the video, so the next source is asked.
    func transcript(for video: URL) async -> SourceTranscript?
}
