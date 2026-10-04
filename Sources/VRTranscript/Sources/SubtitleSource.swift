import Foundation

/// A subtitle file beside the video with its base name: `<base>.srt`,
/// else `<base>.vtt`. One line per cue.
public struct SubtitleSource: TranscriptSource {
    public static let extensions = ["srt", "vtt"]

    public let name = "subtitles"

    public init() {}

    public func prepare(_ video: URL) async {}

    public func transcript(for video: URL) async -> SourceTranscript? {
        let base = video.deletingPathExtension()
        for file in Self.extensions.map(base.appendingPathExtension) {
            guard let data = try? Data(contentsOf: file) else { continue }
            let lines = Self.lines(of: String(decoding: data, as: UTF8.self))
            if !lines.isEmpty { return SourceTranscript(lines: lines) }
        }
        return nil
    }

    /// The cues of an SRT or a WebVTT file, in time order. A cue is a
    /// block of lines with a timing line (`start --> end`) and the words
    /// under it; what is above the timing line (a number, a cue name) and
    /// a block without one (`WEBVTT`, `NOTE`, `STYLE`) are skipped. Tags
    /// (`<i>`, `<v Ada>`) are taken out of the words, and a cue of several
    /// lines becomes one line.
    static func lines(of text: String) -> [TimedLine] {
        var cues: [TimedLine] = []
        var block: [Substring] = []
        func close() {
            defer { block = [] }
            guard let timing = block.firstIndex(where: { $0.contains("-->") }) else { return }
            let ends = block[timing].components(separatedBy: "-->")
            // After the end time, WebVTT may say where the cue is drawn.
            guard ends.count == 2, let start = seconds(ends[0]),
                let end = seconds(ends[1].split(separator: " ", omittingEmptySubsequences: true).first.map(String.init) ?? ""),
                end > start
            else { return }
            let words = block[(timing + 1)...]
                .map { $0.replacing(/<[^>]*>/, with: "").trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            if !words.isEmpty { cues.append(TimedLine(start: start, end: end, text: words)) }
        }
        let unmarked = text.hasPrefix("\u{FEFF}") ? text.dropFirst() : Substring(text)
        for line in unmarked.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            if line.allSatisfy(\.isWhitespace) {
                close()
            } else {
                block.append(line)
            }
        }
        close()
        return cues.sorted { ($0.start, $0.end) < ($1.start, $1.end) }
    }

    /// `00:00:06,067` (SRT), `00:00:06.067` or `00:06.067` (WebVTT) as
    /// seconds; nil for anything else.
    static func seconds(_ stamp: String) -> TimeInterval? {
        let parts = stamp.trimmingCharacters(in: .whitespaces).replacing(",", with: ".").split(separator: ":", omittingEmptySubsequences: false)
        guard (2...3).contains(parts.count) else { return nil }
        var total = 0.0
        for part in parts {
            guard let value = Double(part), value >= 0 else { return nil }
            total = total * 60 + value
        }
        return TimedLine.milliseconds(total)
    }
}
