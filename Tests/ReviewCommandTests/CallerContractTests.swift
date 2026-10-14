import Foundation
@testable import ReviewCommand
import Testing

@Suite("Every caller names a command in the table")
struct CallerContractTests {
    static let places = ["Sources", "docs", "scripts", "site", ".agents/skills/havooch-mate", "README.md", "AGENTS.md"]
    static let extensions: Set = ["swift", "md", "sh", "html", "txt"]

    static let prose: Set = ["command", "commands", "is", "scripts"]

    static let wrappers = ["operator", "listener", "claude_listener", "codex_listener", "settings"]

    static let historyFile = "docs/cli-design.md"
    static let historyHeading = "## Changes from 0.5.1"

    struct Use: CustomStringConvertible {
        var file: String
        var line: Int
        var words: [String]
        var description: String { "\(file):\(line): havooch \(words.joined(separator: " "))" }
    }

    @Test("every havooch <words> in the docs, scripts, site, skill and sources is a command")
    func callers() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        var checked = 0
        for file in try Self.files(under: root) {
            let text = try String(contentsOf: root.appendingPathComponent(file), encoding: .utf8)
            for use in Self.uses(in: text, file: file) {
                checked += 1
                if let problem = Self.problem(with: use.words) {
                    Issue.record("\(use): \(problem)")
                }
            }
        }
        #expect(checked > 100, "the test found only \(checked) callers; does it read the right folders?")
    }

    @Test("the reading finds commands and skips prose, paths and the old names' table", arguments: [
        ("Run `havooch player load <path>`.", [["player", "load"]]),
        ("havooch wait, then ack", [["wait"]]),
        ("the havooch-mate skill and ~/.config/havooch/", []),
        ("the havooch command", [["command"]]),
        ("$ havooch message state m-1 done", [["message", "state"]]),
        ("havooch --help", [[]]),
    ])
    func reading(line: String, words: [[String]]) {
        #expect(Self.uses(in: line, file: "README.md").map(\.words) == words)
    }

    @Test("an old name fails, a new one passes", arguments: [
        (["comment", "add"], false),
        (["status"], false),
        (["send"], false),
        (["message", "add"], true),
        (["player"], true),
        (["command"], true),
        ([], true),
    ])
    func decides(words: [String], passes: Bool) {
        #expect((Self.problem(with: words) == nil) == passes)
    }

    @Test("a script's wrapper call is read, and a comment is not")
    func wrappers() {
        let script = """
        # the operator holds the lease
        run operator comment add "Too fast" --at 0:10
        listener status "$id" done
        operator() { HAVOOCH_CONTROL_KEY="$key" "$cli" "$@"; }
        HAVOOCH_CONTROL_KEY="$key" "$cli" ask "$1" "$2"
        """
        #expect(Self.uses(in: script, file: "scripts/x.sh").map(\.words) == [["comment", "add"], ["status"], [], ["ask"]])
    }

    @Test("the old names' table is skipped, and nothing after it")
    func history() {
        let text = """
        Run havooch player load.
        ## Changes from 0.5.1
        | `havooch player open` | `havooch player load` |
        ## Later
        Run havooch tour open.
        """
        #expect(Self.uses(in: text, file: Self.historyFile).map(\.words) == [["player", "load"], ["tour", "open"]])
    }

    static func problem(with words: [String]) -> String? {
        guard let first = words.first else { return nil }
        if CommandTable.commands.contains(where: { $0.name == first }) { return nil }
        if let group = CommandTable.group(named: first) {
            guard words.count > 1 else { return nil }
            let name = "\(first) \(words[1])"
            if group.commands.contains(where: { $0.name == name }) { return nil }
            return "`\(name)` is not a command of the `\(first)` group"
        }
        if prose.contains(first) { return nil }
        return "`\(first)` is not a command or a group (if it is prose, add it to the prose list)"
    }

    static func files(under root: URL) throws -> [String] {
        var files: [String] = []
        for place in places {
            let url = root.appendingPathComponent(place)
            var isFolder: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder) else {
                Issue.record("\(place) is missing")
                continue
            }
            guard isFolder.boolValue else {
                files.append(place)
                continue
            }
            let walker = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil)
            while let file = walker?.nextObject() as? URL {
                guard extensions.contains(file.pathExtension) else { continue }
                files.append(place + "/" + file.path.dropFirst(url.path.count + 1))
            }
        }
        return files.sorted()
    }

    static func uses(in text: String, file: String) -> [Use] {
        let script = file.hasSuffix(".sh")
        let history = file == historyFile
        var skipping = false
        var uses: [Use] = []
        for (index, line) in text.components(separatedBy: "\n").enumerated() {
            if history, line.hasPrefix("## ") { skipping = line.hasPrefix(historyHeading) }
            if skipping { continue }
            for start in starts(in: line) {
                uses.append(Use(file: file, line: index + 1, words: words(after: line[start...])))
            }
            if script, !line.trimmingCharacters(in: .whitespaces).hasPrefix("#") {
                for start in wrapperStarts(in: line) {
                    uses.append(Use(file: file, line: index + 1, words: words(after: line[start...])))
                }
            }
        }
        return uses
    }

    static func starts(in line: String) -> [String.Index] {
        var starts: [String.Index] = []
        var from = line.startIndex
        while let found = line.range(of: "havooch ", range: from..<line.endIndex) {
            from = found.upperBound
            if found.lowerBound > line.startIndex {
                let before = line[line.index(before: found.lowerBound)]
                if before.isLetter || before.isNumber || "_-.".contains(before) { continue }
            }
            starts.append(found.upperBound)
        }
        return starts
    }

    static func wrapperStarts(in line: String) -> [String.Index] {
        let pattern = #"(?:(?:^|[;&|(!]|\brun)\s*(?:"# + wrappers.joined(separator: "|") + #")|"\$cli")[ \t]+"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(line.startIndex..., in: line)
        return expression.matches(in: line, range: range).compactMap { Range($0.range, in: line)?.upperBound }
    }

    static func words(after rest: Substring) -> [String] {
        var words: [String] = []
        for token in rest.split(whereSeparator: { $0 == " " || $0 == "\t" }) where words.count < 2 {
            guard let first = token.first, first.isLowercase, first.isASCII else { break }
            let word = token.prefix { ($0.isLowercase && $0.isASCII) || $0.isNumber || $0 == "-" }
            words.append(String(word))
            if word.count < token.count { break }
        }
        return words
    }
}
