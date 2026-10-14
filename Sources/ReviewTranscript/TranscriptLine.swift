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

    static func milliseconds(_ seconds: TimeInterval) -> TimeInterval {
        (seconds * 1000).rounded() / 1000
    }
}
