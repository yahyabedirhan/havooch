import Foundation
import ReviewCore
import ReviewStore
import Testing

/// The shipped theme files, the person's theme folder and `settings.json`.
@Suite("Theme files and settings")
struct ThemeFilesTests {
    /// `Packaging/Themes/`, which `make bundle` copies into the app.
    static let shipped = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Packaging/Themes", isDirectory: true)

    private func temporaryLayout() throws -> SupportLayout {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("theme-files-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return SupportLayout(root: root)
    }

    @Test("the app ships Default Light, Default Dark and Dimmed, and every file reads")
    func shippedThemes() {
        let reading = ThemeFiles.read(Self.shipped)
        #expect(reading.problems.isEmpty)
        #expect(Set(reading.files.map(\.name)) == ["Default Light", "Default Dark", "Dimmed"])
        let catalog = ThemeCatalog(builtIn: reading.files, user: [])
        #expect(catalog.problems.isEmpty)
        #expect(catalog.entry(named: "Dimmed")?.file.kind == .dark)
        #expect(catalog.entry(named: "Dimmed")?.file.extends == "Default Dark")
    }

    @Test("each default theme sets every token with a colour that reads, so no token is ever missing")
    func defaultsAreComplete() {
        let files = ThemeFiles.read(Self.shipped).files
        for name in [ThemeCatalog.defaultLight, ThemeCatalog.defaultDark] {
            let file = files.first { $0.name == name }
            for token in ThemeToken.allCases {
                #expect(file?.tokens[token.rawValue].flatMap(ThemeColor.init) != nil, "\(name) has no colour for \(token)")
            }
            let unknown = Set((file?.tokens ?? [:]).keys).subtracting(ThemeToken.allCases.map(\.rawValue))
            #expect(unknown.isEmpty, "\(name) names a token the app doesn't know")
        }
    }

    @Test("no state colour of a shipped theme is pink")
    func noPink() throws {
        let catalog = ThemeCatalog(builtIn: ThemeFiles.read(Self.shipped).files, user: [])
        let states: [ThemeToken] = [.stateQueued, .stateSent, .stateAcknowledged, .stateWorking, .stateDone, .stateFailed]
        for name in catalog.names {
            let theme = try catalog.resolve(name)
            for token in states {
                let color = try #require(theme[token])
                #expect(!Self.isPink(color), "\(name) \(token) is \(color.text)")
            }
        }
    }

    /// A saturated hue between magenta and rose.
    private static func isPink(_ color: ThemeColor) -> Bool {
        let (r, g, b) = (Double(color.red) / 255, Double(color.green) / 255, Double(color.blue) / 255)
        let high = max(r, g, b), low = min(r, g, b)
        guard high - low > 0.08, high == r else { return false }
        // Red is highest; pink leans to blue more than to green.
        let hue = 60 * ((g - b) / (high - low))
        let degrees = hue < 0 ? hue + 360 : hue
        return degrees > 290 && degrees < 350
    }

    @Test("the person's Themes/ folder is read in name order; a file that doesn't read is left out with its reason")
    func userFolder() throws {
        let layout = try temporaryLayout()
        try FileManager.default.createDirectory(at: layout.themesFolder, withIntermediateDirectories: true)
        try Data(##"{"name": "Brown", "kind": "dark", "tokens": {"accent": "#a0522d"}}"##.utf8)
            .write(to: layout.themesFolder.appendingPathComponent("b.json"))
        try Data("{ not json".utf8).write(to: layout.themesFolder.appendingPathComponent("a.json"))
        try Data("ignored".utf8).write(to: layout.themesFolder.appendingPathComponent("notes.txt"))

        let reading = ThemeFiles.user(layout)
        #expect(reading.files.map(\.name) == ["Brown"])
        #expect(reading.found.first?.url.lastPathComponent == "b.json")
        #expect(reading.problems.count == 1)
        #expect(reading.problems.first?.contains("a.json") == true)
    }

    @Test("with no settings file the settings are the defaults; they round-trip, with the pin as null while it follows the system")
    func settingsRoundTrip() throws {
        let layout = try temporaryLayout()
        #expect(try Settings.load(layout) == Settings())

        try Settings(overrides: ["accent": "#123456"]).save(layout)
        let text = try String(contentsOf: layout.settingsFile, encoding: .utf8)
        #expect(text.contains(#""theme" : null"#))

        let pinned = Settings(theme: "Dimmed", overrides: ["accent": "#123456"], sidebarWidth: 360)
        try pinned.save(layout)
        #expect(try Settings.load(layout) == pinned)
    }

    @Test("a settings file written by hand may leave keys out; one that doesn't read is refused, not replaced")
    func handWrittenSettings() throws {
        let layout = try temporaryLayout()
        try Data(##"{"overrides": {"stage": "#000000"}}"##.utf8).write(to: layout.settingsFile)
        #expect(try Settings.load(layout) == Settings(overrides: ["stage": "#000000"]))

        try Data("{ broken".utf8).write(to: layout.settingsFile)
        #expect(throws: Library.Failure.self) { try Settings.load(layout) }
    }
}
