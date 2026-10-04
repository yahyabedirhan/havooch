import Foundation

/// One line of a transcript: what is said from `start` to `end`, in seconds
/// of the video.
public struct TimedLine: Codable, Equatable, Sendable {
    public var start: TimeInterval
    public var end: TimeInterval
    public var text: String

    public init(start: TimeInterval, end: TimeInterval, text: String) {
        self.start = start
        self.end = end
        self.text = text
    }

    /// A time to the millisecond, as the sidecars and the payload give it.
    static func milliseconds(_ seconds: TimeInterval) -> TimeInterval {
        (seconds * 1000).rounded() / 1000
    }
}
