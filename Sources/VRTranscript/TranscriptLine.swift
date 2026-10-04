import Foundation

/// One line of what a video says, with its times in seconds from the
/// video's start.
public struct TranscriptLine: Codable, Equatable, Sendable {
    public var start: Double
    public var end: Double
    public var text: String

    public init(start: Double, end: Double, text: String) {
        self.start = start
        self.end = end
        self.text = text
    }
}

/// The part of a transcript a comment gets: from 15 s before its time to
/// 15 s after.
public enum TranscriptWindow {
    /// How far the window reaches before and after a comment's time, in
    /// seconds.
    public static let reach: Double = 15

    /// The window around `time`, kept inside a video of `duration` seconds.
    public static func around(_ time: Double, duration: Double) -> ClosedRange<Double> {
        let lower = max(0, time - reach)
        return lower...max(lower, min(duration, time + reach))
    }

    /// Every line that is partly or wholly inside `window`, whole and in
    /// time order. A line that only touches the window's edge is outside.
    public static func cut(_ lines: [TranscriptLine], to window: ClosedRange<Double>) -> [TranscriptLine] {
        lines
            .filter { line in
                // A line without a length is a point: inside when the window holds it.
                line.end > line.start
                    ? line.end > window.lowerBound && line.start < window.upperBound
                    : window.contains(line.start)
            }
            .sorted { ($0.start, $0.end) < ($1.start, $1.end) }
    }
}
