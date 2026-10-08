import Foundation
import ReviewConfig
import Testing

/// The targeted writes: the header for a missing file and the theme line.
/// Every other line and comment stays as it was.
@Suite("Writing config.toml")
struct ConfigWriterTests {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("havooch-config-\(UUID().uuidString)", isDirectory: true)
    var location: ConfigLocation { ConfigLocation(folder: folder.appendingPathComponent("config"), home: folder) }

    private func cleanUp() {
        try? FileManager.default.removeItem(at: folder)
    }

    @Test("a theme line has its value replaced, and the comments, the projects and a comment after the value stay")
    func replaces() throws {
        let text = "# mine\nversion = 1\ntheme = 'Dimmed'   # after\n\n# a project\n[[projects]]\nslug = \"a\"\n"
        let edited = try ConfigWriter.settingTheme("Default Dark", in: text)
        #expect(edited == "# mine\nversion = 1\ntheme = \"Default Dark\"   # after\n\n# a project\n[[projects]]\nslug = \"a\"\n")
    }

    @Test("with no theme line, one goes after the last top-level key above the first table")
    func inserts() throws {
        let text = "version = 1\n\n# a project\n[[projects]]\nslug = \"a\"\n"
        #expect(try ConfigWriter.settingTheme("Dimmed", in: text) == "version = 1\ntheme = \"Dimmed\"\n\n# a project\n[[projects]]\nslug = \"a\"\n")
        let header = try ConfigWriter.settingTheme("Dimmed", in: ConfigFile.header)
        #expect(try ConfigFile.decode(header).config.theme == "Dimmed")
        #expect(header == ConfigFile.header.replacingOccurrences(of: "version = 1\n", with: "version = 1\ntheme = \"Dimmed\"\n"))
    }

    @Test("following the system takes the theme line out and keeps the rest")
    func removes() throws {
        let text = "version = 1\ntheme = \"Dimmed\"\n# keep\n"
        #expect(try ConfigWriter.settingTheme(nil, in: text) == "version = 1\n# keep\n")
        #expect(try ConfigWriter.settingTheme(nil, in: "version = 1\n") == "version = 1\n")
    }

    @Test("a file with a problem, or a theme over more than one line, is not written")
    func refuses() {
        #expect(throws: ConfigWriteFailure.self) { try ConfigWriter.settingTheme("Dimmed", in: "version = 2\n") }
        #expect(throws: ConfigWriteFailure.self) { try ConfigWriter.settingTheme("Default Dark", in: "version = 1\ntheme = \"\"\"\nDimmed\"\"\"\n") }
    }

    @Test("a missing file is made from the header, and an existing one is never touched")
    func createsOnce() throws {
        defer { cleanUp() }
        #expect(try location.createIfMissing())
        #expect(try String(contentsOf: location.file, encoding: .utf8) == ConfigFile.header)
        try Data("version = 1\n# mine\n".utf8).write(to: location.file)
        #expect(try !location.createIfMissing())
        #expect(try String(contentsOf: location.file, encoding: .utf8) == "version = 1\n# mine\n")
    }

    @Test("setting the theme writes the file in place, so a symlinked file stays a symlink")
    func setsInPlace() throws {
        defer { cleanUp() }
        let real = folder.appendingPathComponent("dotfiles-config.toml")
        try FileManager.default.createDirectory(at: location.folder, withIntermediateDirectories: true)
        try Data("version = 1 # mine\n".utf8).write(to: real)
        try FileManager.default.createSymbolicLink(at: location.file, withDestinationURL: real)

        try location.setTheme("Dimmed")
        #expect(try String(contentsOf: real, encoding: .utf8) == "version = 1 # mine\ntheme = \"Dimmed\"\n")
        #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: location.file.path)) == real.path)
        try location.setTheme(nil)
        #expect(try String(contentsOf: real, encoding: .utf8) == "version = 1 # mine\n")
    }
}

/// The verdict `config check` prints and the app writes to
/// `config-status.json`.
@Suite("The verdict on config.toml")
struct ConfigVerdictTests {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("havooch-verdict-\(UUID().uuidString)", isDirectory: true)
    var location: ConfigLocation { ConfigLocation(folder: folder.appendingPathComponent("config"), home: folder) }

    @Test("a missing file is accepted with no modification time; a broken one lists each problem with its line")
    func verdicts() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let missing = location.check().verdict
        #expect(missing.accepted)
        #expect(missing.configModified == nil)

        try location.createIfMissing()
        try Data("version = 1\ntheme = 3\nthem = 1\n".utf8).write(to: location.file)
        let (verdict, decoded) = location.check()
        #expect(decoded == nil)
        #expect(!verdict.accepted)
        #expect(verdict.problems == [ConfigIssue(line: 2, message: "`theme` must be a string")])
        #expect(verdict.lines == "config.toml doesn't read: \(location.file.path)\n  problem, line 2: `theme` must be a string\n")
    }

    @Test("config-status.json holds the verdict as JSON, times in whole UTC seconds, a line null when it has none")
    func record() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let verdict = ConfigVerdict(
            checked: Date(timeIntervalSince1970: 1_791_460_000.7), config: URL(fileURLWithPath: "/c/config.toml"),
            configModified: nil, problems: [ConfigIssue(line: nil, message: "no")], warnings: []
        )
        try verdict.write(in: folder)
        let data = try Data(contentsOf: folder.appendingPathComponent(ConfigVerdict.fileName))
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["version"] as? Int == 1)
        #expect(json["accepted"] as? Bool == false)
        #expect(json["checked"] as? String == "2026-10-08T11:46:40Z")
        #expect(json["config"] as? String == "/c/config.toml")
        #expect(json["configModified"] is NSNull)
        let problem = try #require((json["problems"] as? [[String: Any]])?.first)
        #expect(problem["line"] is NSNull)
        #expect(problem["message"] as? String == "no")
    }
}
