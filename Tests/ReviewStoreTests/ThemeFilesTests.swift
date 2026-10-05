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

    @Test("the app ships its own three themes and eight from popular VS Code themes, and every file reads")
    func shippedThemes() {
        let reading = ThemeFiles.read(Self.shipped)
        #expect(reading.problems.isEmpty)
        #expect(Set(reading.files.map(\.name)) == [
            "Default Light", "Default Dark", "Dimmed",
            "GitHub Dark", "GitHub Light", "One Dark Pro", "Dracula", "Tokyo Night",
            "Catppuccin Mocha", "Catppuccin Latte", "Atom One Light",
        ])
        for file in reading.files {
            #expect(reading.found.contains { $0.url.lastPathComponent == "\(file.name).json" }, "\(file.name) is not in a file of its own name")
        }
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

    @Test("every shipped theme resolves every token, names only known tokens and writes each colour so it reads")
    func everyThemeIsComplete() throws {
        let files = ThemeFiles.read(Self.shipped).files
        let catalog = ThemeCatalog(builtIn: files, user: [])
        #expect(catalog.names.count == files.count)
        for file in files {
            for (token, text) in file.tokens {
                #expect(ThemeToken(rawValue: token) != nil, "\(file.name) names \(token), a token the app doesn't know")
                #expect(ThemeColor(text) != nil, "\(file.name) \(token) is \(text), a colour that doesn't read")
            }
            let theme = try catalog.resolve(file.name)
            #expect(theme.colors.count == ThemeToken.allCases.count, "\(file.name) leaves a token unresolved")
        }
    }

    @Test("in every shipped theme the text reads on each surface, and each state stands apart from the surfaces, its glyph and the other states, and the question from every state and the bar")
    func everyThemeReads() throws {
        let catalog = ThemeCatalog(builtIn: ThemeFiles.read(Self.shipped).files, user: [])
        let states: [ThemeToken] = [.stateQueued, .stateSent, .stateAcknowledged, .stateWorking, .stateDone, .stateFailed]
        for name in catalog.names {
            let theme = try catalog.resolve(name)
            func colour(_ token: ThemeToken) throws -> ThemeColor { try #require(theme[token]) }
            for surface: ThemeToken in [.window, .sidebar, .popover, .bar, .header] {
                let primary = Self.contrast(try colour(.textPrimary), try colour(surface))
                let secondary = Self.contrast(try colour(.textSecondary), try colour(surface))
                #expect(primary >= 6,"\(name): textPrimary on \(surface) is \(primary):1")
                #expect(secondary >= 4.5, "\(name): textSecondary on \(surface) is \(secondary):1")
            }
            for token in states + [.accent, .question] {
                for surface: ThemeToken in [.sidebar, .popover] {
                    let ratio = Self.contrast(try colour(token), try colour(surface))
                    #expect(ratio >= 2.5, "\(name): \(token) on \(surface) is \(ratio):1")
                }
                let glyph = Self.contrast(try colour(.textOnAccent), try colour(token))
                #expect(glyph >= 3, "\(name): textOnAccent on \(token) is \(glyph):1")
            }
            // The question's pin on the player bar stands apart from every
            // state's pin, and shows on the bar as a mark should (3:1).
            let questionOnBar = Self.contrast(try colour(.question), try colour(.bar))
            #expect(questionOnBar >= 3, "\(name): question on bar is \(questionOnBar):1")
            for state in states {
                let distance = Self.distance(try colour(.question), try colour(state))
                #expect(distance >= 10, "\(name): question and \(state) are \(distance) apart")
            }
            for (index, one) in states.enumerated() {
                for other in states[(index + 1)...] {
                    let distance = Self.distance(try colour(one), try colour(other))
                    #expect(distance >= 10, "\(name): \(one) and \(other) are \(distance) apart")
                }
            }
        }
    }

    /// The WCAG contrast ratio of two opaque colours, from 1 to 21.
    private static func contrast(_ one: ThemeColor, _ other: ThemeColor) -> Double {
        let (a, b) = (luminance(one), luminance(other))
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    private static func linear(_ byte: UInt8) -> Double {
        let c = Double(byte) / 255
        return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }

    private static func luminance(_ color: ThemeColor) -> Double {
        0.2126 * linear(color.red) + 0.7152 * linear(color.green) + 0.0722 * linear(color.blue)
    }

    /// How far apart two colours look: the CIE76 distance in CIELAB.
    private static func distance(_ one: ThemeColor, _ other: ThemeColor) -> Double {
        let (a, b) = (lab(one), lab(other))
        return ((a.0 - b.0) * (a.0 - b.0) + (a.1 - b.1) * (a.1 - b.1) + (a.2 - b.2) * (a.2 - b.2)).squareRoot()
    }

    private static func lab(_ color: ThemeColor) -> (Double, Double, Double) {
        let (r, g, b) = (linear(color.red), linear(color.green), linear(color.blue))
        let x = (0.4124 * r + 0.3576 * g + 0.1805 * b) / 0.95047
        let y = 0.2126 * r + 0.7152 * g + 0.0722 * b
        let z = (0.0193 * r + 0.1192 * g + 0.9505 * b) / 1.08883
        func f(_ t: Double) -> Double { t > 0.008856 ? cbrt(t) : 7.787 * t + 16.0 / 116 }
        return (116 * f(y) - 16, 500 * (f(x) - f(y)), 200 * (f(y) - f(z)))
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
