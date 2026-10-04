import Foundation

/// Where a video's transcript comes from: a sidecar file, or speech
/// recognition. Every source is behind this one interface, so a better one
/// replaces another without a change to what asks.
public protocol Transcriber: Sendable {
    /// The lines of `video` that are partly or wholly inside `window`
    /// (seconds from the video's start), whole and in time order.
    func lines(for video: URL, in window: ClosedRange<Double>) async throws -> [TranscriptLine]
}

/// Why a source gave no transcript, as one line.
public struct TranscriptFailure: LocalizedError, Equatable, Sendable {
    public var reason: String

    public init(_ reason: String) {
        self.reason = reason
    }

    public var errorDescription: String? { reason }
}

extension TranscriptLine {
    /// A line with its times rounded to the millisecond and its text on one
    /// line without space around it, as every source gives it; nil when no
    /// text is left, or a time isn't a number.
    public static func tidy(start: Double, end: Double, text: String) -> TranscriptLine? {
        let words = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !words.isEmpty, start.isFinite, end.isFinite else { return nil }
        let start = (start * 1000).rounded() / 1000
        return TranscriptLine(start: start, end: max(start, (end * 1000).rounded() / 1000), text: words)
    }
}
