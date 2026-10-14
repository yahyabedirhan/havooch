import Foundation

enum ConfigPathComponent: Hashable, Sendable {
    case key(String)
    case index(Int)
}

typealias ConfigPath = [ConfigPathComponent]

extension Array where Element == ConfigPathComponent {
    var dotted: String {
        var out = ""
        for component in self {
            switch component {
            case .key(let key):
                if !out.isEmpty { out += "." }
                out += key
            case .index(let index):
                out += "[\(index)]"
            }
        }
        return out
    }
}

/// Finds which line of the file a key path sits on, so validation messages
/// can say "line 14". TOMLDecoder parses the document but doesn't expose
/// where a value came from, so this does a light second pass over the text:
/// it records every table header (`[a.b]`, `[[projects]]`, with array-of-
/// tables indices) and every `key = value` line, skipping over strings,
/// comments and multi-line arrays. It only runs on text TOMLDecoder already
/// accepted.
struct TOMLSourceMap {
    struct Entry {
        var path: ConfigPath
        var line: Int
        var endLine: Int
        var isHeader: Bool
    }

    private(set) var entries: [Entry] = []
    private let lines: [Substring]

    init(_ text: String) {
        lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        var scanner = Scanner(Array(text.unicodeScalars))
        var section: ConfigPath = []
        var arrayIndex: [String: Int] = [:]

        while true {
            scanner.skipBlankLinesAndComments()
            guard let char = scanner.peek() else { break }
            let startLine = scanner.line
            if char == "[" {
                let isArray = scanner.peek(1) == "["
                scanner.advance()
                if isArray { scanner.advance() }
                let keys = scanner.readKey(until: "]")
                scanner.skipToLineEnd()
                var path: ConfigPath = []
                for (position, key) in keys.enumerated() {
                    path.append(.key(key))
                    if isArray && position == keys.count - 1 {
                        let next = (arrayIndex[path.dotted] ?? -1) + 1
                        arrayIndex[path.dotted] = next
                        path.append(.index(next))
                    } else if let current = arrayIndex[path.dotted] {
                        path.append(.index(current))
                    }
                }
                section = path
                entries.append(Entry(path: path, line: startLine, endLine: startLine, isHeader: true))
            } else {
                let keys = scanner.readKey(until: "=")
                if scanner.peek() == "=" {
                    scanner.advance()
                    scanner.skipValue()
                } else {
                    scanner.skipToLineEnd()
                }
                entries.append(Entry(
                    path: section + keys.map { .key($0) },
                    line: startLine,
                    endLine: scanner.line,
                    isHeader: false
                ))
            }
        }

        let headerLines = entries.filter(\.isHeader).map(\.line)
        for position in entries.indices where entries[position].isHeader {
            let start = entries[position].line
            entries[position].endLine = (headerLines.first { $0 > start } ?? (lines.count + 1)) - 1
        }
    }

    func line(for path: ConfigPath, value: String? = nil, occurrence: Int = 0) -> Int? {
        var prefix = path
        while !prefix.isEmpty {
            let match = entries.first { $0.path == prefix }
                ?? entries.first { $0.path.starts(with: prefix) }
            if let entry = match {
                if let value, let found = line(of: value, occurrence: occurrence, in: entry.line...max(entry.line, entry.endLine)) {
                    return found
                }
                return entry.line
            }
            prefix.removeLast()
        }
        return nil
    }

    private func line(of value: String, occurrence: Int, in range: ClosedRange<Int>) -> Int? {
        let needles = ["\"\(value)\"", "'\(value)'"]
        var seen = 0
        for number in range where number <= lines.count {
            let text = lines[number - 1]
            seen += needles.reduce(0) { $0 + text.components(separatedBy: $1).count - 1 }
            if seen > occurrence { return number }
        }
        return nil
    }
}

private struct Scanner {
    private let text: [Unicode.Scalar]
    private var position = 0
    private(set) var line = 1

    init(_ text: [Unicode.Scalar]) { self.text = text }

    func peek(_ offset: Int = 0) -> Unicode.Scalar? {
        position + offset < text.count ? text[position + offset] : nil
    }

    mutating func advance() {
        guard position < text.count else { return }
        if text[position] == "\n" { line += 1 }
        position += 1
    }

    mutating func skipSpaces() {
        while let char = peek(), char == " " || char == "\t" || char == "\r" { advance() }
    }

    mutating func skipToLineEnd() {
        while let char = peek(), char != "\n" { advance() }
    }

    mutating func skipBlankLinesAndComments() {
        while true {
            skipSpaces()
            switch peek() {
            case "#": skipToLineEnd()
            case "\n": advance()
            default: return
            }
        }
    }

    mutating func readKey(until terminator: Unicode.Scalar) -> [String] {
        var parts: [String] = []
        while true {
            skipSpaces()
            guard let char = peek(), char != terminator, char != "\n" else { return parts }
            if char == "." {
                advance()
            } else if char == "\"" || char == "'" {
                parts.append(readQuotedKey(char))
            } else if Self.isBare(char) {
                var key = ""
                while let next = peek(), Self.isBare(next) {
                    key.unicodeScalars.append(next)
                    advance()
                }
                parts.append(key)
            } else {
                advance()
            }
        }
    }

    private mutating func readQuotedKey(_ quote: Unicode.Scalar) -> String {
        advance()
        var key = ""
        while let char = peek(), char != quote, char != "\n" {
            if quote == "\"" && char == "\\" {
                advance()
                if let escaped = peek(), escaped != "\n" {
                    key.unicodeScalars.append(escaped)
                    advance()
                }
                continue
            }
            key.unicodeScalars.append(char)
            advance()
        }
        if peek() == quote { advance() }
        return key
    }

    mutating func skipValue() {
        var depth = 0
        while let char = peek() {
            switch char {
            case "\n":
                if depth == 0 { return }
                advance()
            case "#":
                skipToLineEnd()
            case "\"", "'":
                skipString(char)
            case "[", "{":
                depth += 1
                advance()
            case "]", "}":
                depth = max(0, depth - 1)
                advance()
            default:
                advance()
            }
        }
    }

    private mutating func skipString(_ quote: Unicode.Scalar) {
        if peek(1) == quote && peek(2) == quote {
            advance(); advance(); advance()
            while peek() != nil {
                if peek() == quote && peek(1) == quote && peek(2) == quote {
                    advance(); advance(); advance()
                    while peek() == quote { advance() }
                    return
                }
                if quote == "\"" && peek() == "\\" { advance() }
                advance()
            }
            return
        }
        advance()
        while let char = peek(), char != quote, char != "\n" {
            if quote == "\"" && char == "\\" { advance() }
            advance()
        }
        if peek() == quote { advance() }
    }

    private static func isBare(_ char: Unicode.Scalar) -> Bool {
        switch char {
        case "A"..."Z", "a"..."z", "0"..."9", "-", "_": true
        default: false
        }
    }
}
