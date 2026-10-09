import Foundation
@testable import ReviewApp
import ReviewConfig
import ReviewCore
import ReviewLease
import ReviewStore
import ReviewWire
import Testing

/// The theme as the app runs it: the built-in themes, the person's own in
/// `themes/` beside `config.toml`, the pin in `config.toml`, the reload on
/// a change, and `theme list`, `theme set` and `state` over the control
/// server.
@Suite("Themes in the app", .serialized)
struct ThemeDeskTests {
    nonisolated static let operatorAgent = Holder(key: "operator", name: "Claude Code", place: "/work")

    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("havooch-tests-\(UUID().uuidString)", isDirectory: true)
    var layout: SupportLayout { SupportLayout(root: root.appendingPathComponent("support", isDirectory: true)) }
    /// Where `HAVOOCH_SUPPORT_DIR` puts the settings: the support folder's `config/`.
    var location: ConfigLocation { ConfigLocation(folder: layout.root.appendingPathComponent("config"), home: root) }

    private func cleanUp() {
        try? FileManager.default.removeItem(at: root)
    }

    private func model() -> (WindowModel, ControlServer) {
        let model = AppModel(environment: [SupportFolder.overrideVariable: layout.root.path]).makeWindow()
        let server = ControlServer(
            socket: URL(fileURLWithPath: "/nowhere/control.sock"), app: model.app, listeners: { model.app.listeners },
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
        try FileManager.default.createDirectory(at: location.themesFolder, withIntermediateDirectories: true)
        try Data(json.utf8).write(to: location.themesFolder.appendingPathComponent(name))
    }

    private func configText() throws -> String {
        try String(contentsOf: location.file, encoding: .utf8)
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

    @Test("theme set pins a theme for every appearance in config.toml's theme line, keeps it across a restart, and theme set system unpins")
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

        // Only the theme line is written: the header's comments stay.
        #expect(try configText() == ConfigFile.header.replacingOccurrences(of: "version = 1\n", with: "version = 1\ntheme = \"Dimmed\"\n"))
        #expect(!FileManager.default.fileExists(atPath: layout.settingsFile.path))

        // A new run reads the pin from config.toml.
        let (again, againServer) = self.model()
        #expect(again.themes.theme.name == "Dimmed")

        #expect(await send(.themeSet(name: "system"), againServer) == .done("theme follows the system (Default Light)\n"))
        #expect(again.themes.pinned == nil)
        #expect(try configText() == ConfigFile.header)
    }

    @Test("an unknown theme is refused, and nothing changes")
    func unknownTheme() async throws {
        defer { cleanUp() }
        let (model, server) = model()
        let reply = await send(.themeSet(name: "Purple"), server)
        #expect(reply == .refused("no theme Purple; havooch theme list names them"))
        #expect(model.themes.theme.name == "Default Light")
        #expect(try configText() == ConfigFile.header)
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

    @Test("a pin no theme has follows the system, with a problem in theme list")
    func unknownPin() async throws {
        defer { cleanUp() }
        try location.createIfMissing()
        try Data("version = 1\ntheme = \"Purple\"\n".utf8).write(to: location.file)
        let (model, server) = model()
        #expect(model.themes.theme.name == "Default Light")
        #expect(model.themes.pinned == nil)
        let list = await send(.themeList, server)
        #expect(list.output.contains("left out: config.toml pins the theme Purple, which no theme file has"))
    }

    @Test("state reports the fill of filled controls: the theme's accentFill, which white text reads on")
    func reportsTheFill() throws {
        defer { cleanUp() }
        try location.createIfMissing()
        try Data("version = 1\ntheme = \"Default Dark\"\n".utf8).write(to: location.file)
        let (model, _) = model()
        #expect(model.themes.report.accentFill == "#48689d")
        let data = try JSONEncoder().encode(model.themes.report)
        #expect(try object(String(decoding: data, as: UTF8.self))["accentFill"] as? String == "#48689d")
    }

    @Test("every prominent button is a filled button on accentFill: no view uses the prominent style but through filledButton")
    func prominentButtonsAreFilled() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/ReviewApp", isDirectory: true)
        let files = try #require(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" && $0.lastPathComponent != "Palette.swift" }
        var found: [String] = []
        var filled = 0
        for file in files {
            let lines = try String(contentsOf: file, encoding: .utf8).components(separatedBy: "\n")
            for (number, line) in lines.enumerated() {
                let code = line.components(separatedBy: "//").first ?? ""
                if code.contains("borderedProminent") || code.contains(".prominent") {
                    found.append("\(file.lastPathComponent):\(number + 1): \(line.trimmingCharacters(in: .whitespaces))")
                }
                if code.contains(".filledButton(palette)") { filled += 1 }
            }
        }
        #expect(found.isEmpty, "prominent buttons that skip filledButton:\n\(found.joined(separator: "\n"))")
        // Send, Open a Video… twice, the two Saves and the rest.
        #expect(filled >= 6)
    }

    @Test("a split action is the one SplitButton, on accentFill with white text: no view builds a menu with a primary action of its own")
    func splitActionsAreTheSplitButton() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/ReviewApp", isDirectory: true)
        let files = try #require(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }
        var inline: [String] = []
        var uses = 0
        var control = ""
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            if file.lastPathComponent == "SplitButton.swift" {
                control = text
                continue
            }
            for (number, line) in text.components(separatedBy: "\n").enumerated() {
                let code = line.components(separatedBy: "//").first ?? ""
                if code.contains("primaryAction:") || code.contains("primaryAction {") {
                    inline.append("\(file.lastPathComponent):\(number + 1): \(line.trimmingCharacters(in: .whitespaces))")
                }
                if code.contains("SplitButton(") { uses += 1 }
            }
        }
        #expect(inline.isEmpty, "split buttons built inline:\n\(inline.joined(separator: "\n"))")
        // White text on the fill filledButton uses, which reads at 4.5:1 or more.
        #expect(control.contains(".background(palette[.accentFill])"))
        #expect(control.contains(".foregroundStyle(palette.textOnFill)"))
        // The comment popover's Queue or Answer.
        #expect(uses >= 1)
    }

    @Test("a theme file written while the app runs is read at once, and so is a pin saved in config.toml")
    func reloadsOnChange() async throws {
        defer { cleanUp() }
        let (model, _) = model()
        model.themes.startWatching()
        model.config.startWatching()
        defer {
            model.themes.stopWatching()
            model.config.stopWatching()
        }

        try writeTheme(##"{"name": "Brown", "kind": "dark", "tokens": {"accent": "#c08a5b"}}"##, as: "brown.json")
        await eventually { model.themes.catalog.entry(named: "Brown") != nil }
        #expect(model.themes.catalog.entry(named: "Brown") != nil)

        try Data("version = 1\ntheme = \"Brown\"\n".utf8).write(to: location.file, options: .atomic)
        await eventually { model.themes.theme.name == "Brown" }
        #expect(model.themes.theme[.accent] == ThemeColor("#c08a5b"))

        // Edited in place, as an editor that doesn't replace the file saves it.
        let file = location.themesFolder.appendingPathComponent("brown.json")
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

    @Test("a save of the outbox in the support folder doesn't read the themes again; a new pin in config.toml does")
    func ignoresOtherFiles() async throws {
        defer { cleanUp() }
        let (model, _) = model()
        model.themes.startWatching()
        model.config.startWatching()
        defer {
            model.themes.stopWatching()
            model.config.stopWatching()
        }
        let before = model.themes.reloads

        // Replaced, as the outbox is saved, then written in place.
        try Data("{}".utf8).write(to: layout.formerOutboxFile, options: .atomic)
        try Data("{}".utf8).write(to: layout.formerOutboxFile)
        try? await Task.sleep(for: .milliseconds(500))
        #expect(model.themes.reloads == before)

        try Data("version = 1\ntheme = \"Default Dark\"\n".utf8).write(to: location.file, options: .atomic)
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
        // A named colour or hierarchical style:.white,.secondary, …
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
