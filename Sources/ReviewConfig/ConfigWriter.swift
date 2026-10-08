import Foundation

// The targeted writes of `config.toml` (ADR 0002). Havooch never rewrites
// the file as a whole: TOMLDecoder only decodes, and a rewrite would lose
// the person's comments. Each write changes its own lines, and is refused
// unless the result reads back as the file's settings with only that change.
// After Swift Lab's `ConfigurationFile+Edit.swift` (yahyabedirhan/swift-lab
// at ccb82cb).

/// Why a write of `config.toml` or of the verdict didn't happen.
public struct ConfigWriteFailure: Error, Equatable, Sendable {
    public var reason: String

    public init(_ reason: String) {
        self.reason = reason
    }
}

/// The text edits, pure: text in, text out.
public enum ConfigWriter {
    /// `text` with the top-level `theme` set to `name`, or taken out for
    /// nil, every other line and comment kept:
    ///
    /// - a `theme` line has its value replaced, a comment after it kept;
    /// - with no `theme` line, `theme = "<name>"` goes after the last
    ///   top-level key above the first table;
    /// - nil takes the `theme` line out.
    ///
    /// Refused: a file that doesn't read, a `theme` value that isn't one
    /// string on one line, and a result that wouldn't read back as the
    /// same settings with only the theme changed.
    public static func settingTheme(_ name: String?, in text: String) throws(ConfigWriteFailure) -> String {
        let before: ConfigFile.Decoded
        do throws(ConfigProblems) {
            before = try ConfigFile.decode(text)
        } catch {
            throw ConfigWriteFailure("config.toml has a problem: \(error.line)")
        }
        if let name, name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ConfigWriteFailure("a theme needs a name")
        }
        guard before.config.theme != name else { return text }

        let map = TOMLSourceMap(text)
        var lines = text.components(separatedBy: "\n")
        if let entry = map.entries.first(where: { $0.path == [.key("theme")] && !$0.isHeader }) {
            guard entry.line == entry.endLine, let parts = themeLine(lines[entry.line - 1]) else {
                throw ConfigWriteFailure("line \(entry.line) of config.toml doesn't set `theme` as one string on one line")
            }
            if let name {
                lines[entry.line - 1] = parts.lead + ConfigReader.tomlString(name) + parts.rest
            } else {
                lines.remove(at: entry.line - 1)
            }
        } else if let name {
            let firstHeader = map.entries.first(where: \.isHeader)?.line ?? Int.max
            let lastTopKey = map.entries.filter { !$0.isHeader && $0.path.count == 1 && $0.line < firstHeader }.map(\.endLine).max()
            let line = "theme = \(ConfigReader.tomlString(name))"
            if let lastTopKey {
                lines.insert(line, at: lastTopKey)
            } else if firstHeader != Int.max {
                lines.insert(contentsOf: [line, ""], at: firstHeader - 1)
            } else {
                // Comments only, or nothing: at the end, on a line of its own.
                if lines.last == "" { lines.removeLast() }
                lines.append(line)
                lines.append("")
            }
        }
        let edited = lines.joined(separator: "\n")

        // Read back: only the theme may change.
        var expected = before.config
        expected.theme = name
        guard let after = try? ConfigFile.decode(edited), after.config == expected, after.warnings == before.warnings else {
            throw ConfigWriteFailure("the edit wouldn't read back as the same settings with only the theme changed")
        }
        return edited
    }

    /// A `theme = "…"` line split around its string value: what comes
    /// before the value, and what comes after it (a comment). Nil when the
    /// value isn't one quoted string.
    static func themeLine(_ line: String) -> (lead: String, rest: String)? {
        guard let equals = line.firstIndex(of: "=") else { return nil }
        var index = line.index(after: equals)
        while index < line.endIndex, line[index] == " " || line[index] == "\t" { index = line.index(after: index) }
        guard index < line.endIndex else { return nil }
        let quote = line[index]
        guard quote == "\"" || quote == "'" else { return nil }
        // A triple-quoted string may span lines: not one string on one line.
        if line[index...].hasPrefix(String(repeating: quote, count: 3)) { return nil }
        var end = line.index(after: index)
        while end < line.endIndex, line[end] != quote {
            if quote == "\"", line[end] == "\\" { end = line.index(after: end) }
            if end < line.endIndex { end = line.index(after: end) }
        }
        guard end < line.endIndex else { return nil }
        return (String(line[..<index]), String(line[line.index(after: end)...]))
    }
}

extension ConfigLocation {
    /// Creates the file, and its folder, from `ConfigFile.header` when it
    /// is missing. An existing file is never touched. Returns whether it
    /// made the file.
    @discardableResult
    public func createIfMissing() throws(ConfigWriteFailure) -> Bool {
        let fileManager = FileManager.default
        guard !fileManager.fileExists(atPath: file.path) else { return false }
        do {
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            // `withoutOverwriting`: a file an editor wrote meanwhile wins.
            try Data(ConfigFile.header.utf8).write(to: file, options: .withoutOverwriting)
            return true
        } catch {
            guard !fileManager.fileExists(atPath: file.path) else { return false }
            throw ConfigWriteFailure("couldn't create \(file.path): \(error.localizedDescription)")
        }
    }

    /// Sets the file's `theme` to `name`, or takes it out for nil
    /// (`ConfigWriter.settingTheme`), creating the file from the header
    /// when it is missing. The file is written in place, never renamed
    /// over, so a symlinked file stays a symlink, and only when it still
    /// holds the text that was read.
    public func setTheme(_ name: String?) throws(ConfigWriteFailure) {
        try createIfMissing()
        try edit { text throws(ConfigWriteFailure) in try ConfigWriter.settingTheme(name, in: text) }
    }

    /// Runs one targeted edit: `change` gets the file's text and gives the
    /// new text. Nothing is written when the text is the same, or when the
    /// file changed after it was read.
    func edit(_ change: (String) throws(ConfigWriteFailure) -> String) throws(ConfigWriteFailure) {
        let handle: FileHandle
        do {
            handle = try FileHandle(forUpdating: file)
        } catch {
            throw ConfigWriteFailure("couldn't open \(file.path): \(error.localizedDescription)")
        }
        defer { try? handle.close() }
        // Writers take turns on a lock of the file itself.
        flock(handle.fileDescriptor, LOCK_EX)
        defer { flock(handle.fileDescriptor, LOCK_UN) }
        do {
            let data = try handle.readToEnd() ?? Data()
            guard let text = String(data: data, encoding: .utf8) else { throw ConfigWriteFailure("\(file.path) isn't UTF-8 text") }
            let edited = try change(text)
            guard edited != text else { return }
            try handle.truncate(atOffset: 0)
            try handle.write(contentsOf: Data(edited.utf8))
        } catch let failure as ConfigWriteFailure {
            throw failure
        } catch {
            throw ConfigWriteFailure("couldn't write \(file.path): \(error.localizedDescription)")
        }
    }
}
