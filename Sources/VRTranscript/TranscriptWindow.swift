import Foundation

/// The part of a transcript a comment gets: the lines said from 15 s
/// before its time to 15 s after.
public enum TranscriptWindow {
    public static let radius: TimeInterval = 15

    /// The window around a comment at `time`. It starts at the video's
    /// start at the earliest, and may run past its end.
    public static func around(_ time: TimeInterval) -> ClosedRange<TimeInterval> {
        max(0, time - radius)...(time + radius)
    }

    /// The lines that are said at some moment of `window`, whole and in
    /// time order: a line that begins before the window or ends after it
    /// is kept as it is. A line that only touches the window's edge isn't
    /// in it.
    public static func cut(_ lines: [TimedLine], to window: ClosedRange<TimeInterval>) -> [TimedLine] {
        lines
            .filter { $0.end > window.lowerBound && $0.start < window.upperBound }
            .sorted { ($0.start, $0.end) < ($1.start, $1.end) }
    }
}
