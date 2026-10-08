import Foundation
import ReviewCommand
import ReviewConfig
import ReviewWire
import Testing

/// `config path` and `config check` read the file themselves: no request
/// reaches the app, and they answer while it isn't running. With
/// `HAVOOCH_SUPPORT_DIR` set, the file is in that folder's `config/`.
@Suite("The config commands")
struct ConfigCommandTests {
    private func file(_ run: Run) -> URL {
        run.support.appendingPathComponent("config/config.toml")
    }

    private func write(_ text: String, _ run: Run) throws {
        try FileManager.default.createDirectory(at: file(run).deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: file(run))
    }

    private func object(_ text: String) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    }

    @Test("config path prints the file in the moved support folder, with no app, and makes nothing")
    func path() throws {
        let run = Run()
        defer { run.cleanUp() }
        #expect(run("config", "path") == CommandResult(output: file(run).path + "\n"))
        let json = try object(run("config", "path", "--json").output)
        #expect(json["config"] as? String == file(run).path)
        #expect(json["themes"] as? String == run.support.appendingPathComponent("config/themes").path)
        #expect(json["exists"] as? Bool == false)
        #expect(run.transport.requests.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: file(run).path))
    }

    @Test("config check accepts a missing file and a valid one, with its warnings")
    func accepts() throws {
        let run = Run()
        defer { run.cleanUp() }
        #expect(run("config", "check") == CommandResult(output: "config.toml reads: \(file(run).path)\n"))
        try write("version = 1\ntheme = \"Dimmed\"\ncolour = 1\n", run)
        let result = run("config", "check")
        #expect(result.exitCode == 0)
        #expect(result.output.contains("warning, line 3: unknown setting `colour` (ignored)"))
        #expect(run.transport.requests.isEmpty)
    }

    @Test("config check lists each problem with its line and exits 1; --json prints the verdict as config-status.json holds it")
    func rejects() throws {
        let run = Run()
        defer { run.cleanUp() }
        try write("version = 1\n\ntheme = 3\n", run)
        let result = run("config", "check")
        #expect(result.exitCode == 1)
        #expect(result.output == "config.toml doesn't read: \(file(run).path)\n  problem, line 3: `theme` must be a string\n")

        let json = run("config", "check", "--json")
        #expect(json.exitCode == 1)
        let verdict = try object(json.output)
        #expect(verdict["accepted"] as? Bool == false)
        #expect(verdict["config"] as? String == file(run).path)
        let problem = try #require((verdict["problems"] as? [[String: Any]])?.first)
        #expect(problem["line"] as? Int == 3)
    }

    @Test("config dismiss asks the app to close the settings notice")
    func dismiss() {
        let run = Run { _, _ in .success(.done("the settings notice is closed\n")) }
        defer { run.cleanUp() }
        #expect(run("config", "dismiss") == CommandResult(output: "the settings notice is closed\n"))
        #expect(run.transport.requests == [.configDismiss])
    }

    @Test("the config commands take no words")
    func usage() {
        let run = Run()
        defer { run.cleanUp() }
        #expect(run("config", "path", "x").exitCode == 64)
        #expect(run("config", "check", "x").exitCode == 64)
        #expect(run("config", "dismiss", "x").exitCode == 64)
        #expect(CommandTable.usageText.contains("havooch config check"))
    }
}
