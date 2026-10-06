import Foundation
@testable import ReviewApp
import ReviewCore
import ReviewLease
import ReviewStore
import ReviewWire
import Testing

/// The theme as the app runs it: the built-in themes, the person's own,
/// the pin and the overrides in `settings.json`, the reload on a change,
/// and `theme list`, `theme set` and `state` over the control server.
@Suite("Themes in the app", .serialized)
struct ThemeDeskTests {
    nonisolated static let operatorAgent = Holder(key: "operator", name: "Claude Code", place: "/work")

    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("havooch-tests-\(UUID().uuidString)", isDirectory: true)
    var layout: SupportLayout { SupportLayout(root: root.appendingPathComponent("support", isDirectory: true)) }

    private func cleanUp() {
        try? FileManager.default.removeItem(at: root)
    }

    private func model() -> (AppModel, ControlServer) {
        let model = AppModel(environment: [SupportFolder.overrideVariable: layout.root.path])
        let server = ControlServer(
            socket: URL(fileURLWithPath: "/nowhere/control.sock"), app: model, listeners: { model.listeners },
            screenshotter: ControlServerTests.FakeScreenshotter(), quit: {}
        )
        return (model, server)
    }

    private func send(_ request: ControlRequest, _ server: ControlServer, json: Bool = false) async -> ControlReply {
        await server.reply(to: request.sent(by: Self.operatorAgent, json: json)).reply
    }

    private func object(_ text: String) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    }

    private func writeTheme(_ json: String, as name: String) throws {
        try FileManager.default.createDirectory(at: layout.themesFolder, withIntermediateDirectories: true)
        try Data(json.utf8).write(to: layout.themesFolder.appendingPathComponent(name))
    }

    private func eventually(_ condition: () -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(5)
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    @Test("with no pin the theme follows the system appearance: Default Light, then Default Dark")
    func followsTheSystem() {
        defer { cleanUp() }
        let (model, _) = model()
        #expect(model.themes.theme.name == "Default Light")
        #expect(model.themes.theme.isComplete)
        model.themes.setAppearance(.dark)
        #expect(model.themes.theme.name == "Default Dark")
        #expect(model.themes.theme.kind == .dark)
    }

    @Test("theme set pins a theme for every appearance, keeps it across a restart, and theme set system unpins")
    func pinAndUnpin() async throws {
        defer { cleanUp() }
        let (model, server) = model()

        let reply = await send(.themeSet(name: "dimmed"), server)
        #expect(reply == .done("theme Dimmed pinned\n"))
        #expect(model.themes.theme.name == "Dimmed")
        model.themes.setAppearance(.light)
        #expect(model.themes.theme.name == "Dimmed")

        let state = try object(model.state().json)
        let theme = try #require(state["theme"] as? [String: Any])
        #expect(theme["active"] as? String == "Dimmed")
        #expect(theme["kind"] as? String == "dark")
        #expect(theme["pinned"] as? String == "Dimmed")
        #expect(theme["appearance"] as? String == "light")

        // A new run reads the pin from settings.json.
        let (again, againServer) = self.model()
        #expect(again.themes.theme.name == "Dimmed")

        #expect(await send(.themeSet(name: "system"), againServer) == .done("theme follows the system (Default Light)\n"))
        #expect(again.themes.pinned == nil)
        #expect(try Settings.load(layout).theme == nil)
    }

    @Test("an unknown theme is refused, and nothing changes")
    func unknownTheme() async throws {
        defer { cleanUp() }
        let (model, server) = model()
        let reply = await send(.themeSet(name: "Purple"), server)
        #expect(reply == .refused("no theme Purple; havooch theme list names them"))
        #expect(model.themes.theme.name == "Default Light")
        #expect(!FileManager.default.fileExists(atPath: layout.settingsFile.path))
    }

    @Test("theme list names the built-in and the user themes, marks the active one, and a user theme replaces a built-in of its name")
    func list() async throws {
        defer { cleanUp() }
        try writeTheme(##"{"name": "Brown", "kind": "dark", "extends": "Default Dark", "tokens": {"accent": "#c08a5b"}}"##, as: "brown.json")
        try writeTheme(##"{"name": "Dimmed", "kind": "dark", "tokens": {"stage": "#333333"}}"##, as: "dimmed.json")
        try writeTheme("{ broken", as: "broken.json")
        let (_, server) = model()

        let lines = await send(.themeList, server)
        #expect(lines.ok)
        let defaultLine = lines.output.split(separator: "\n").first { $0.hasPrefix("Default Light ") }
        #expect(defaultLine?.split(separator: " ") == ["Default", "Light", "light", "built-in", "active"])
        #expect(lines.output.contains("left out: "))

        let reply = await send(.themeList, server, json: true)
        let themes = try #require(try object(reply.output)["themes"] as? [[String: Any]])
        #expect(themes.map { $0["name"] as? String } == [
            "Atom One Light", "Brown", "Catppuccin Latte", "Catppuccin Mocha", "Default Dark", "Default Light", "Dimmed",
            "Dracula", "GitHub Dark", "GitHub Light", "One Dark Pro", "Tokyo Night",
        ])
        #expect(themes.first { $0["name"] as? String == "Dimmed" }?["source"] as? String == "user")
        #expect(themes.first { $0["name"] as? String == "Default Dark" }?["source"] as? String == "built-in")
        #expect(themes.first { $0["name"] as? String == "Default Light" }?["active"] as? Bool == true)
        #expect((try object(reply.output)["problems"] as? [String])?.count == 1)
    }

    @Test("overrides in settings.json apply on top of the active theme")
    func overrides() throws {
        defer { cleanUp() }
        try Settings(theme: "Dimmed", overrides: ["accent": "#123456", "nonsense": "#ffffff"]).save(layout)
        let (model, _) = model()
        #expect(model.themes.theme.name == "Dimmed")
        #expect(model.themes.theme[.accent] == ThemeColor("#123456"))
        #expect(model.themes.report.overrides == 2)
    }

    @Test("a theme file written while the app runs is read at once, and so is a change to settings.json")
    func reloadsOnChange() async throws {
        defer { cleanUp() }
        let (model, _) = model()
        model.themes.startWatching()
        defer { model.themes.stopWatching() }

        try writeTheme(##"{"name": "Brown", "kind": "dark", "tokens": {"accent": "#c08a5b"}}"##, as: "brown.json")
        await eventually { model.themes.catalog.entry(named: "Brown") != nil }
        #expect(model.themes.catalog.entry(named: "Brown") != nil)

        try Settings(theme: "Brown").save(layout)
        await eventually { model.themes.theme.name == "Brown" }
        #expect(model.themes.theme[.accent] == ThemeColor("#c08a5b"))

        // Edited in place, as an editor that doesn't replace the file saves it.
        let file = layout.themesFolder.appendingPathComponent("brown.json")
        let handle = try FileHandle(forWritingTo: file)
        try handle.truncate(atOffset: 0)
        try handle.write(contentsOf: Data(##"{"name": "Brown", "kind": "dark", "tokens": {"accent": "#a0522d"}}"##.utf8))
        try handle.close()
        await eventually { model.themes.theme[.accent] == ThemeColor("#a0522d") }
        #expect(model.themes.theme[.accent] == ThemeColor("#a0522d"))

        // A broken file falls back to the default of the appearance.
        try Data("{ broken".utf8).write(to: file)
        await eventually { model.themes.theme.name == "Default Light" }
        #expect(model.themes.theme.name == "Default Light")
    }

    @Test("a save of the outbox in the support folder doesn't read the themes again; a new settings.json does")
    func ignoresOtherFiles() async throws {
        defer { cleanUp() }
        let (model, _) = model()
        model.themes.startWatching()
        defer { model.themes.stopWatching() }
        let before = model.themes.reloads

        // Replaced, as the outbox is saved, then written in place.
        try Data("{}".utf8).write(to: layout.outboxFile, options: .atomic)
        try Data("{}".utf8).write(to: layout.outboxFile)
        try? await Task.sleep(for: .milliseconds(500))
        #expect(model.themes.reloads == before)

        try Settings(theme: "Default Dark").save(layout)
        await eventually { model.themes.theme.name == "Default Dark" }
        #expect(model.themes.reloads > before)
    }

    @Test("no view uses a raw colour: every colour comes from the palette, which makes colours from numbers and system surfaces only")
    func noRawColours() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/ReviewApp", isDirectory: true)
        let files = try #require(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }
        #expect(files.count > 20)
        #expect(files.contains { $0.lastPathComponent == "Palette.swift" })
        var found: [String] = []
        for file in files {
            let isPalette = file.lastPathComponent == "Palette.swift"
            let lines = try String(contentsOf: file, encoding: .utf8).components(separatedBy: "\n")
            for (number, line) in lines.enumerated() {
                let code = line.components(separatedBy: "//").first ?? ""
                if RawColour.matches(code, inPalette: isPalette) {
                    found.append("\(file.lastPathComponent):\(number + 1): \(line.trimmingCharacters(in: .whitespaces))")
                }
            }
        }
        #expect(found.isEmpty, "raw colours outside the palette's own ways:\n\(found.joined(separator: "\n"))")
    }

    @Test("the palette may make a colour from numbers or a system surface; the same code anywhere else is a raw colour, and a named colour is raw in the palette too", arguments: [
        "Color(nsColor: Self.systemColor(token))", "AnyShapeStyle(.ultraThickMaterial), fill: AnyShapeStyle(self[token].opacity(0.8)))", "Color(.sRGB, white: 0.5)",
        "Color(nsColor: .keyboardFocusIndicatorColor)",
        "NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)", "func nsColor(_ token: ThemeToken) -> NSColor {", "return Color(", "return NSColor(",
        "green: Double(color.green) / 255",
    ])
    func paletteAllowances(code: String) {
        #expect(RawColour.matches(code))
        #expect(!RawColour.matches(code, inPalette: true))
        #expect(RawColour.matches("\(code) Color.black", inPalette: true))
        #expect(RawColour.matches("AnyShapeStyle(.ultraThinMaterial)", inPalette: true))
        #expect(RawColour.matches("Color(nsColor: .controlAccentColor)", inPalette: true))
    }

    @Test("the raw-colour check finds the ways a view could name a colour, and lets tokens and font weights pass", arguments: [
        ("Color.black", true), ("Color(nsColor: .windowBackgroundColor)", true), (".foregroundStyle(.secondary)", true),
        (".fill(.white)", true), ("NSColor.labelColor", true), (".background(.ultraThinMaterial)", true),
        (".foregroundStyle(.tint)", true), (".fill(.tint.opacity(0.2))", true), ("Color.accentColor", true),
        (".foregroundStyle(palette[.textSecondary])", false), (".tint(palette[.accent])", false),
        (".font(.system(size: 7, weight: .black))", false), ("Color.clear", false), ("private var fill: Color {", false),
        (".background(.clear)", false),
    ])
    func rawColourCheck(code: String, isRaw: Bool) {
        #expect(RawColour.matches(code) == isRaw)
    }
}

/// The ways Swift code names a colour without a theme token.
enum RawColour {
    private static let patterns = [
        // A colour made or named on the type: Color.black, Color(red:…), Color(nsColor:).
        #"\bColor\s*(\.(?!clear\b)\w|\()"#,
        #"\bNSColor\b"#, #"\bCGColor\b"#,
        // A named colour or hierarchical style: .white, .secondary, …
        #"(?<!weight: )\.(white|black|gray|grey|red|orange|yellow|green|mint|teal|cyan|blue|indigo|purple|pink|brown|primary|secondary|tertiary|quaternary|quinary|accentColor)\b(?!\s*:)"#,
        // The tint as a style (the `.tint(…)` modifier is fine).
        #"\.tint\b(?!\s*\()"#,
        #"\b\w*Material\b"#,
    ].map { try! NSRegularExpression(pattern: $0) }

    /// What `Palette.swift` alone may write: a colour from a theme's
    /// numbers (and the grey of a missing token), the `NSColor` it returns,
    /// a `system` surface through `systemColor` or the ultra-thick material,
    /// and the system's focus ring.
    private static let paletteAllowances = [
        #"\bColor\(\s*($|\.sRGB\b|nsColor:\s*Self\.systemColor\(|nsColor:\s*\.keyboardFocusIndicatorColor\))"#,
        #"\bNSColor\(\s*($|(srgbRed|white):)"#,
        #"->\s*NSColor\b"#,
        // A theme colour's own components.
        #"\bcolor\.(red|green|blue|alpha)\b"#,
        #"AnyShapeStyle\(\.ultraThickMaterial\)"#,
    ].map { try! NSRegularExpression(pattern: $0) }

    /// Whether `code` names a raw colour; in the palette, after taking out
    /// what the palette alone may write.
    static func matches(_ code: String, inPalette: Bool = false) -> Bool {
        var code = code
        if inPalette {
            for allowance in paletteAllowances {
                code = allowance.stringByReplacingMatches(in: code, range: NSRange(code.startIndex..., in: code), withTemplate: "")
            }
        }
        let range = NSRange(code.startIndex..., in: code)
        return patterns.contains { $0.firstMatch(in: code, range: range) != nil }
    }
}
