import Foundation

/// The part of a transcript a comment gets: from 15 s before its time to
/// 15 s after.
public enum TranscriptWindow {
    /// How far the window reaches each way from the comment's time.
    public static let reach: TimeInterval = 15

    /// The window around `time`, kept inside a video of `duration` seconds.
    public static func range(around time: TimeInterval, duration: TimeInterval) -> ClosedRange<TimeInterval> {
        let lower = max(0, time - reach)
        return lower...max(lower, min(duration, time + reach))
    }

    /// The lines that overlap `window`. A line is kept whole, also when
    /// only a part of it is inside: a cut sentence reads badly. A line that
    /// only touches the window's edge is outside.
    public static func cut(_ lines: [TranscriptLine], to window: ClosedRange<TimeInterval>) -> [TranscriptLine] {
        lines.filter { $0.end > window.lowerBound && $0.start < window.upperBound }
    }

    /// The lines a comment at `time` gets.
    public static func cut(_ lines: [TranscriptLine], around time: TimeInterval, duration: TimeInterval) -> [TranscriptLine] {
        cut(lines, to: range(around: time, duration: duration))
    }
}
