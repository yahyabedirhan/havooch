import Foundation
@testable import ReviewApp
import ReviewConfig
import ReviewCore
import ReviewStore
import ReviewWire
import Testing

/// `config.toml` as the app runs it (ADR 0002): made from the header on
/// the first launch, a valid save applied at once, a broken one rejected
/// with the last valid settings kept, the verdict in `config-status.json`,
/// the one-time move of an older build's settings, and app state kept out
/// of the file. Every run is on a scratch support folder, so the settings
/// are in its `config/`, never in the person's `~/.config/havooch`.
@Suite("The settings file in the app", .serialized)
struct ConfigDeskTests {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("havooch-tests-\(UUID().uuidString)", isDirectory: true)
    var layout: SupportLayout { SupportLayout(root: root.appendingPathComponent("support", isDirectory: true)) }
    var location: ConfigLocation { ConfigLocation(folder: layout.root.appendingPathComponent("config"), home: root) }
    var statusFile: URL { layout.root.appendingPathComponent(ConfigVerdict.fileName) }

    private func cleanUp() {
        try? FileManager.default.removeItem(at: root)
    }

    private func model() -> WindowModel {
        AppModel(environment: [SupportFolder.overrideVariable: layout.root.path]).makeWindow()
    }

    private func object(_ url: URL) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    private func object(_ text: String) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    }

    private func save(_ text: String) throws {
        // As most editors save: a new file renamed over the old one.
        try Data(text.utf8).write(to: location.file, options: .atomic)
    }

    private func eventually(_ condition: () -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(5)
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    @Test("the first launch makes config.toml from the header in the moved support folder, accepts it, and state --json reports it")
    func firstLaunch() throws {
        defer { cleanUp() }
        let model = model()
        #expect(try String(contentsOf: location.file, encoding: .utf8) == ConfigFile.header)
        #expect(model.config.notice == nil)

        let verdict = try object(statusFile)
        #expect(verdict["accepted"] as? Bool == true)
        #expect(verdict["config"] as? String == location.file.path)

        let config = try #require(try object(model.state().json)["config"] as? [String: Any])
        #expect(config["path"] as? String == location.file.path)
        #expect(config["themes"] as? String == location.themesFolder.path)
        #expect(config["status"] as? String == statusFile.path)
        #expect(config["accepted"] as? Bool == true)
        #expect((config["problems"] as? [Any])?.isEmpty == true)
        #expect(config["notice"] is NSNull)
        #expect(model.state().lines.contains("config: \(location.file.path), applied"))
    }

    @Test("a valid save applies at once; a broken one keeps the last valid settings, lists each problem with its line, and puts up a notice once")
    func liveReload() async throws {
        defer { cleanUp() }
        let model = model()
        model.config.startWatching()
        defer { model.config.stopWatching() }

        try save("version = 1\ntheme = \"Dimmed\"\n")
        await eventually { model.themes.theme.name == "Dimmed" }
        #expect(model.themes.theme.name == "Dimmed")
        #expect(try object(statusFile)["accepted"] as? Bool == true)

        try save("version = 1\ntheme = \"Dimmed\"\n\ntheme = 3\n")
        await eventually { !model.config.verdict.accepted }
        #expect(model.themes.theme.name == "Dimmed")
        #expect(model.config.config.theme == "Dimmed")
        let verdict = try object(statusFile)
        #expect(verdict["accepted"] as? Bool == false)
        let problem = try #require((verdict["problems"] as? [[String: Any]])?.first)
        #expect(problem["line"] as? Int == 4)
        #expect(model.problem == nil)
        #expect(model.config.notice?.kind == .rejected)
        #expect(model.config.notice?.title == "config.toml wasn't applied")
        #expect(model.config.notice?.lines.first?.hasPrefix("Line 4: invalid TOML") == true)
        #expect(model.config.notice?.lines.first?.hasSuffix("..") == false)

        // The same problems again don't come up again; theme set doesn't write over the file.
        #expect(model.app.dismissConfigNotice())
        #expect(!model.app.dismissConfigNotice())
        #expect(model.config.reload() == .rejected)
        #expect(model.config.notice == nil)
        #expect(throws: AppRefusal.self) { try model.app.setTheme("Default Dark") }

        // A new problem comes up; a file that reads again takes it away.
        try save("version = 1\ntheme = 4\n")
        await eventually { model.config.notice != nil }
        #expect(model.config.notice?.lines.first == "Line 2: `theme` must be a string.")
        try save("version = 1\ntheme = \"Default Dark\"\n")
        await eventually { model.themes.theme.name == "Default Dark" }
        #expect(model.config.verdict.accepted)
        #expect(model.config.notice == nil)
    }

    @Test("a launch on a file with a problem runs with every default and puts up a notice")
    func brokenAtLaunch() throws {
        defer { cleanUp() }
        try location.createIfMissing()
        try save("version = 1\nthem = \"Dimmed\"\ntheme = \"\"\n")
        let model = model()
        #expect(model.themes.theme.name == "Default Light")
        #expect(!model.config.verdict.accepted)
        #expect(model.config.notice?.lines.contains { $0.hasPrefix("Line 3: `theme` is empty") } == true)
    }

    @Test("an older build's settings move once: the pin into config.toml, the themes into themes/, overrides dropped with a note; the sidebar width stays")
    func movesFormerSettings() throws {
        defer { cleanUp() }
        try FileManager.default.createDirectory(at: layout.formerThemesFolder, withIntermediateDirectories: true)
        try Data(##"{"name": "Brown", "kind": "dark", "extends": "Default Dark", "tokens": {"accent": "#c08a5b"}}"##.utf8)
            .write(to: layout.formerThemesFolder.appendingPathComponent("brown.json"))
        try Data(##"{"overrides": {"accent": "#123456", "window": "#000000"}, "sidebarWidth": 300, "theme": "Brown"}"##.utf8)
            .write(to: layout.settingsFile)

        let model = model()
        #expect(model.themes.theme.name == "Brown")
        #expect(model.themes.theme[.accent] == ThemeColor("#c08a5b"))
        #expect(model.sidebarWidth == 300)
        #expect(try ConfigFile.decode(String(contentsOf: location.file, encoding: .utf8)).config.theme == "Brown")
        #expect(FileManager.default.fileExists(atPath: location.themesFolder.appendingPathComponent("brown.json").path))
        #expect(!FileManager.default.fileExists(atPath: layout.formerThemesFolder.path))
        #expect(try Settings.former(layout) == nil)
        #expect(try Settings.load(layout) == Settings(sidebarWidth: 300))
        #expect(model.config.notes.count == 2)
        #expect(model.config.notes.contains { $0.hasPrefix("The 2 token overrides in settings.json no longer apply. To keep them,") })
        // A notice in the window, never a modal alert.
        #expect(model.problem == nil)
        #expect(model.config.notice == ConfigDesk.Notice(kind: .moved, title: "Your settings moved to config.toml", lines: model.config.notes))
        let config = try #require(try object(model.state().json)["config"] as? [String: Any])
        #expect(config["notes"] as? [String] == model.config.notes)
        #expect((config["notice"] as? [String: Any])?["kind"] as? String == "moved")

        // Once: the next launch has nothing to move.
        let again = self.model()
        #expect(again.config.notes.isEmpty)
        #expect(again.config.notice == nil)
        #expect(again.themes.theme.name == "Brown")
    }

    @Test("a pin config.toml has already wins over settings.json's, which is retired all the same")
    func configPinWins() throws {
        defer { cleanUp() }
        try location.createIfMissing()
        try save("version = 1\ntheme = \"Dimmed\"\n")
        try Data(##"{"overrides": {}, "theme": "Dracula"}"##.utf8).write(to: layout.settingsFile)
        let model = model()
        #expect(model.themes.theme.name == "Dimmed")
        #expect(model.config.notes.isEmpty)
        #expect(try Settings.former(layout) == nil)
    }

    @Test("while config.toml has a problem, settings.json keeps its theme for a later launch")
    func waitsForAValidFile() throws {
        defer { cleanUp() }
        try location.createIfMissing()
        try save("version = 1\ntheme = 3\n")
        try Data(##"{"theme": "Dracula"}"##.utf8).write(to: layout.settingsFile)
        let model = model()
        #expect(try Settings.former(layout) == Settings.Former(theme: "Dracula"))
        #expect(model.config.notes.first?.hasPrefix("The theme in settings.json moves into config.toml once config.toml reads.") == true)
    }

    @Test("app state stays in the support folder: the sidebar width, recents and reviews never reach config.toml")
    func appStateStaysOut() async throws {
        defer { cleanUp() }
        let model = model()
        try await model.open(MessageTests.fixture)
        model.keepSidebarWidth(400)
        model.savePosition()
        #expect(try String(contentsOf: location.file, encoding: .utf8) == ConfigFile.header)
        #expect(try Settings.load(layout).sidebarWidth == 400)
        #expect(FileManager.default.fileExists(atPath: layout.recentsFile.path))
    }

    @Test("config dismiss closes the notice over the control server, under the lease, and says when none was up")
    func dismissCommand() async throws {
        defer { cleanUp() }
        try Data(##"{"overrides": {"accent": "#123456"}}"##.utf8).write(to: { try? FileManager.default.createDirectory(at: layout.root, withIntermediateDirectories: true); return layout.settingsFile }())
        let model = model()
        #expect(model.config.notes == ["The 1 token override in settings.json no longer applies. To keep it, write a theme that extends another in \(location.themesFolder.path)."])
        let server = ControlServer(
            socket: URL(fileURLWithPath: "/nowhere/control.sock"), app: model.app, listeners: { model.listeners },
            screenshotter: ControlServerTests.FakeScreenshotter(), quit: {}
        )
        let holder = ThemeDeskTests.operatorAgent
        #expect(await server.reply(to: ControlRequest.configDismiss.sent(by: holder, json: false)).reply == .done("the settings notice is closed\n"))
        #expect(model.config.notice == nil)
        #expect(await server.reply(to: ControlRequest.configDismiss.sent(by: holder, json: false)).reply == .done("no settings notice was up\n"))
    }
}
