import Foundation

/// One line of a transcript: what's said from `start` to `end`, in seconds
/// from the video's start.
public struct TranscriptLine: Codable, Equatable, Sendable {
    public var start: TimeInterval
    public var end: TimeInterval
    public var text: String

    public init(start: TimeInterval, end: TimeInterval, text: String) {
        self.start = start
        self.end = end
        self.text = text
    }

    /// `seconds` to the millisecond, as every source gives its times: a
    /// scene's frames and a subtitle's cue then name the same moment.
    static func milliseconds(_ seconds: TimeInterval) -> TimeInterval {
        (seconds * 1000).rounded() / 1000
    }
}
