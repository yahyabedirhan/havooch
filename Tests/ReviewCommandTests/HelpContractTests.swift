import Foundation
@testable import ReviewCommand
import ReviewWire
import Testing

/// The contract between the command table and its help: the help is made
/// from the table, so what it shows is what the code runs.
@Suite("The help and the command table agree")
struct HelpContractTests {
    @Test("every example parses as its own command, and asks for what the command's role says")
    func examples() {
        let run = Run()
        defer { run.cleanUp() }
        for command in CommandTable.commands {
            #expect(!command.examples.isEmpty, "`\(command.name)` has no example")
            for example in command.examples {
                let words = command.name.split(separator: " ").map(String.init) + Self.words(example)
                switch HavoochCLI.read(words, environment: run.environment) {
                case .invocation(let found, let invocation, _):
                    #expect(found.name == command.name, "`havooch \(command.name) \(example)` runs `\(found.name)`")
                    #expect(invocation.role == command.role, "`havooch \(command.name) \(example)` has another role")
                case .answered(let result):
                    Issue.record("`havooch \(command.name) \(example)` doesn't parse: \(result.error)")
                }
            }
        }
    }

    @Test("each summary is one line that starts with a verb, and no help uses a dash as punctuation")
    func summaries() {
        for command in CommandTable.commands {
            #expect(!command.summary.contains("\n"))
            #expect(command.summary.first?.isLowercase == true, "`\(command.name)`'s summary starts with a verb")
            #expect(!command.summary.contains(" as a click"), "`\(command.name)`'s summary names a click")
        }
        let texts = [Help.top()] + CommandTable.groups.map(Help.help(for:)) + CommandTable.commands.map(Help.help(for:))
        for text in texts {
            #expect(!text.contains("\u{2014}") && !text.contains("\u{2013}") && !text.contains(" - "))
        }
    }

    @Test("the top help's lines fit in 100 columns")
    func width() {
        for line in Help.top().split(separator: "\n") {
            #expect(line.count <= 100, "too wide: \(line)")
        }
    }

    @Test("the top help's --window line comes from the table: none when no command takes it")
    func windowLine() {
        #expect(Help.top().contains("  --window <id>   act on that window, not the key one\n"))
        let noWindow = CommandTable.groups.map { group in
            var group = group
            group.commands = group.commands.map { command in
                var command = command
                command.takesWindow = false
                return command
            }
            return group
        }
        #expect(!Help.top(noWindow).contains("--window <id>   "))
        #expect(!Help.help(for: noWindow[CommandTable.groups.firstIndex { $0.name == "player" } ?? 0]).contains("--window"))
    }

    @Test("help --json lists every command with its name, usage, summary, role, options and whether it takes --window")
    func json() throws {
        let run = Run()
        defer { run.cleanUp() }
        let result = run("help", "--json")
        #expect(result.exitCode == 0)
        let table = try #require(try JSONSerialization.jsonObject(with: Data(result.output.utf8)) as? [String: Any])
        let groups = try #require(table["groups"] as? [[String: Any]])
        let commands = groups.flatMap { $0["commands"] as? [[String: Any]] ?? [] }
        #expect(commands.compactMap { $0["name"] as? String } == CommandTable.commands.map(\.name))
        for command in commands {
            #expect((command["usage"] as? String)?.hasPrefix("havooch ") == true)
            #expect(command["summary"] is String)
            #expect(["free", "person", "operator", "listener"].contains(command["role"] as? String ?? ""))
            #expect(command["options"] is [String])
            #expect(command["takesWindow"] is Bool)
        }
        let state = try #require(commands.first { $0["name"] as? String == "message state" })
        #expect(state["role"] as? String == "listener")
        #expect(state["takesWindow"] as? Bool == false)
    }

    @Test("the top help matches its stored snapshot")
    func topSnapshot() throws {
        try Self.matches(help(), snapshot: "top-help.txt")
    }

    @Test("the player group's help matches its stored snapshot")
    func playerSnapshot() throws {
        try Self.matches(help("player"), snapshot: "player-help.txt")
    }

    /// Compares `text` with the stored snapshot `name`. With
    /// `HAVOOCH_RECORD_SNAPSHOTS=1` it writes the snapshot instead.
    static func matches(_ text: String, snapshot name: String) throws {
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Snapshots", isDirectory: true).appendingPathComponent(name)
        if ProcessInfo.processInfo.environment["HAVOOCH_RECORD_SNAPSHOTS"] == "1" {
            try text.write(to: file, atomically: true, encoding: .utf8)
            return
        }
        let stored = try String(contentsOf: file, encoding: .utf8)
        #expect(text == stored, "the help differs from Snapshots/\(name)")
    }

    /// `line` split into words as a shell splits it: at spaces, with a
    /// double-quoted text one word.
    static func words(_ line: String) -> [String] {
        var words: [String] = []
        var word = ""
        var quoted = false
        var started = false
        for character in line {
            switch character {
            case "\"":
                quoted.toggle()
                started = true
            case " " where !quoted:
                if started { words.append(word) }
                word = ""
                started = false
            default:
                word.append(character)
                started = true
            }
        }
        if started { words.append(word) }
        return words
    }
}
