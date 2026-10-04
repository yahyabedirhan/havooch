import Foundation

/// A `.srt` or `.vtt` subtitle file: one line per cue.
public struct SubtitleSource: Transcriber {
    public var file: URL

    public init(file: URL) {
        self.file = file
    }

    public func lines(for video: URL, in window: ClosedRange<Double>) async throws -> [TranscriptLine] {
        let text: String
        do {
            text = String(decoding: try Data(contentsOf: file), as: UTF8.self)
        } catch {
            throw TranscriptFailure("couldn't read \(file.lastPathComponent): \(error.localizedDescription)")
        }
        return TranscriptWindow.cut(Self.lines(of: text), to: window)
    }

    /// The cues of the subtitle text `text`, SubRip or WebVTT alike. A cue
    /// is a timing line (`00:00:06,067 --> 00:00:14,333`) and the lines
    /// under it up to an empty one, joined by a space, with their tags
    /// (`<i>`, `<v Name>`) taken out. Everything else is skipped:
    /// cue numbers and names, the `WEBVTT` header, notes and styles.
    public static func lines(of text: String) -> [TranscriptLine] {
        var cues: [TranscriptLine] = []
        var timing: (start: Double, end: Double)?
        var words: [String] = []

        func close() {
            if let timing, let line = TranscriptLine.tidy(start: timing.start, end: timing.end, text: words.joined(separator: " ")) {
                cues.append(line)
            }
            timing = nil
            words = []
        }

        // A file may start with a byte order mark, and end its lines the Windows way.
        for row in text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            let row = row.trimmingCharacters(in: .whitespaces.union(["\u{FEFF}"]))
            if row.isEmpty {
                close()
            } else if let found = Self.timing(row) {
                close()
                timing = found
            } else if timing != nil {
                words.append(plain(row))
            }
        }
        close()
        return cues.sorted { ($0.start, $0.end) < ($1.start, $1.end) }
    }

    /// The two times of a timing line, or nil for any other line. What
    /// follows the second time (WebVTT's cue settings) is left out.
    static func timing(_ row: String) -> (start: Double, end: Double)? {
        guard let arrow = row.range(of: "-->") else { return nil }
        let after = row[arrow.upperBound...].split(whereSeparator: \.isWhitespace).first.map(String.init) ?? ""
        guard
            let start = seconds(row[..<arrow.lowerBound].trimmingCharacters(in: .whitespaces)),
            let end = seconds(after),
            end >= start
        else { return nil }
        return (start, end)
    }

    /// `00:00:06,067`, `00:06.067` or `6.067` as seconds: hours and minutes
    /// may be left out, and the fraction follows a comma or a dot.
    static func seconds(_ text: String) -> Double? {
        let parts = text.replacingOccurrences(of: ",", with: ".").split(separator: ":", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count) else { return nil }
        var total = 0.0
        for part in parts {
            guard !part.isEmpty, part.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == ".") }), let value = Double(part) else { return nil }
            total = total * 60 + value
        }
        return total
    }

    /// A cue's line without its tags.
    static func plain(_ row: String) -> String {
        var text = ""
        var inTag = false
        for character in row {
            if inTag {
                inTag = character != ">"
            } else if character == "<" {
                inTag = true
            } else {
                text.append(character)
            }
        }
        return text
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&nbsp;", with: " ")
    }
}
