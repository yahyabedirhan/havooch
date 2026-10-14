import Foundation

/// A subtitle sidecar with the video's base name: `.srt`, else `.vtt`. One
/// line a cue.
public struct SubtitleSource: Transcriber {
    public init() {}

    /// The sidecar of `video`: `<base name>.srt`, else `<base name>.vtt`.
    public static func file(for video: URL) -> URL? {
        let base = video.deletingPathExtension()
        return [base.appendingPathExtension("srt"), base.appendingPathExtension("vtt")]
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    public func transcript(of video: VideoFile) -> Transcript? {
        guard let file = Self.file(for: video.url), let text = try? String(contentsOf: file, encoding: .utf8) else { return nil }
        let lines = Self.parse(text)
        return lines.isEmpty ? nil : Transcript(source: .subtitles, lines: lines, complete: true)
    }

    /// The cues of a SubRip or WebVTT file, in time order. Both formats are
    /// blocks with a blank line between them, and a cue is the block with a
    /// `start --> end` line: what's above it (a number, a name) is dropped,
    /// what's under it is the text. A block without that line (`WEBVTT`,
    /// `NOTE`, `STYLE`) is no cue.
    public static func parse(_ text: String) -> [TranscriptLine] {
        let rows = text.replacing("\r\n", with: "\n").replacing("\r", with: "\n").replacing("\u{FEFF}", with: "")
            .split(separator: "\n", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
        var lines: [TranscriptLine] = []
        for block in rows.split(separator: "", omittingEmptySubsequences: true) {
            guard let timing = block.firstIndex(where: { $0.contains("-->") }) else { continue }
            let times = block[timing].components(separatedBy: "-->")
            guard times.count == 2, let start = seconds(times[0]),
                  let end = seconds(times[1].split(separator: " ").first.map(String.init) ?? "")
            else { continue }
            let words = block[(timing + 1)...].map(plain).filter { !$0.isEmpty }.joined(separator: " ")
            if !words.isEmpty, end >= start { lines.append(TranscriptLine(start: start, end: end, text: words)) }
        }
        return lines.sorted { $0.start < $1.start }
    }

    static func seconds(_ text: String) -> TimeInterval? {
        let parts = text.trimmingCharacters(in: .whitespaces).replacing(",", with: ".").split(separator: ":", omittingEmptySubsequences: false)
        guard (2...3).contains(parts.count) else { return nil }
        var seconds = 0.0
        for part in parts {
            guard let value = Double(part), value.isFinite, value >= 0 else { return nil }
            seconds = seconds * 60 + value
        }
        guard seconds.isFinite else { return nil }
        return TranscriptLine.milliseconds(seconds)
    }

    private static func plain(_ row: String) -> String {
        row.replacing(/<[^>]*>|\{\\[^}]*\}/, with: "").trimmingCharacters(in: .whitespaces)
    }
}
