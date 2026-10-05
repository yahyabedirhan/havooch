import Foundation
import ReviewCore
import Testing

/// How a theme resolves to every token: its own values, the themes it
/// extends, the default theme of its kind, then the overrides.
@Suite("Theme resolution")
struct ThemeTests {
    /// A default theme with every token set to `colour`.
    private static func complete(_ name: String, _ kind: ThemeKind, _ colour: String) -> ThemeFile {
        ThemeFile(name: name, kind: kind, tokens: Dictionary(uniqueKeysWithValues: ThemeToken.allCases.map { ($0.rawValue, colour) }))
    }

    private static let light = complete(ThemeCatalog.defaultLight, .light, "#ffffff")
    private static let dark = complete(ThemeCatalog.defaultDark, .dark, "#000000")

    private static func colour(_ text: String) -> ThemeColor {
        ThemeColor(text)!
    }

    @Test("a colour reads as #rrggbb or #rrggbbaa, prints back the same, and anything else doesn't read")
    func colours() {
        #expect(ThemeColor("#5B7DB1") == ThemeColor(red: 0x5B, green: 0x7D, blue: 0xB1))
        #expect(ThemeColor("#5b7db180")?.alpha == 0x80)
        #expect(ThemeColor("#5b7db1")?.text == "#5b7db1")
        #expect(ThemeColor("#5b7db180")?.text == "#5b7db180")
        for bad in ["5b7db1", "#5b7", "#5b7db1f", "#gg0000", "", "#5b7db1800"] {
            #expect(ThemeColor(bad) == nil, "\(bad)")
        }
    }

    @Test("a token the theme sets wins; a missing one comes from the theme it extends, then from the default of its kind")
    func extendsThenFallback() throws {
        let base = ThemeFile(name: "Base", kind: .dark, tokens: ["accent": "#111111", "stage": "#222222"])
        let child = ThemeFile(name: "Child", kind: .dark, extends: "Base", tokens: ["accent": "#333333"])
        let catalog = ThemeCatalog(builtIn: [Self.light, Self.dark], user: [base, child])

        let theme = try catalog.resolve("Child")
        #expect(theme.name == "Child")
        #expect(theme.kind == .dark)
        #expect(theme[.accent] == Self.colour("#333333"))
        #expect(theme[.stage] == Self.colour("#222222"))
        #expect(theme[.sidebar] == Self.colour("#000000"))
        #expect(theme.colors.count == ThemeToken.allCases.count)
    }

    @Test("the fallback is the default theme of the theme's own kind, even when it extends a theme of the other kind")
    func fallbackFollowsTheKind() throws {
        let paper = ThemeFile(name: "Paper", kind: .light, extends: ThemeCatalog.defaultDark, tokens: [:])
        let lone = ThemeFile(name: "Lone", kind: .light, tokens: ["accent": "#123456"])
        let catalog = ThemeCatalog(builtIn: [Self.light, Self.dark], user: [paper, lone])

        #expect(try catalog.resolve("Lone")[.window] == Self.colour("#ffffff"))
        // Every token of the dark default is set, so nothing is left for the light one.
        #expect(try catalog.resolve("Paper")[.window] == Self.colour("#000000"))
    }

    @Test("overrides apply on top of the active theme; an unknown token or a colour that doesn't read is ignored")
    func overrides() throws {
        let catalog = ThemeCatalog(builtIn: [Self.light, Self.dark], user: [])
        let theme = try catalog.resolve(
            ThemeCatalog.defaultDark, overrides: ["accent": "#abcdef", "nonsense": "#ffffff", "stage": "blue"]
        )
        #expect(theme[.accent] == Self.colour("#abcdef"))
        #expect(theme[.stage] == Self.colour("#000000"))
    }

    @Test("a colour in a theme that doesn't read counts as missing; a token name the app doesn't know is ignored")
    func badValuesFallBack() throws {
        let odd = ThemeFile(name: "Odd", kind: .light, tokens: ["accent": "red", "sparkle": "#123456"])
        let catalog = ThemeCatalog(builtIn: [Self.light, Self.dark], user: [odd])
        #expect(try catalog.resolve("Odd")[.accent] == Self.colour("#ffffff"))
    }

    @Test("a theme whose extends loops, or names no theme, is left out with its reason")
    func loopsAndMissingParents() {
        let one = ThemeFile(name: "One", kind: .dark, extends: "Two", tokens: [:])
        let two = ThemeFile(name: "Two", kind: .dark, extends: "One", tokens: [:])
        let orphan = ThemeFile(name: "Orphan", kind: .dark, extends: "Nobody", tokens: [:])
        let fine = ThemeFile(name: "Fine", kind: .dark, extends: ThemeCatalog.defaultDark, tokens: [:])
        let catalog = ThemeCatalog(builtIn: [Self.light, Self.dark], user: [one, two, orphan, fine])

        #expect(catalog.names == ["Default Dark", "Default Light", "Fine"])
        #expect(catalog.problems.count == 3)
        #expect(catalog.problems.contains { $0.contains("Orphan") && $0.contains("Nobody") })
        #expect(throws: ThemeRefusal.unknown("One")) { try catalog.resolve("One") }
    }

    @Test("a user theme with a built-in name replaces it; names are matched without regard to case")
    func userReplacesBuiltIn() throws {
        let mine = ThemeFile(name: "Default Dark", kind: .dark, tokens: ["accent": "#654321"])
        let catalog = ThemeCatalog(builtIn: [Self.light, Self.dark], user: [mine])

        #expect(catalog.entry(named: "default dark")?.source == .user)
        #expect(catalog.names == ["Default Dark", "Default Light"])
        let theme = try catalog.resolve("Default Dark")
        #expect(theme[.accent] == Self.colour("#654321"))
        // Its missing tokens still come from the built-in default it replaced.
        #expect(theme[.stage] == Self.colour("#000000"))
    }

    @Test("the active theme is the pinned one while it exists, else the default of the system appearance")
    func active() {
        let dimmed = ThemeFile(name: "Dimmed", kind: .dark, extends: ThemeCatalog.defaultDark, tokens: [:])
        let catalog = ThemeCatalog(builtIn: [Self.light, Self.dark, dimmed], user: [])

        #expect(catalog.active(pinned: nil, appearance: .light) == "Default Light")
        #expect(catalog.active(pinned: nil, appearance: .dark) == "Default Dark")
        #expect(catalog.active(pinned: "dimmed", appearance: .light) == "Dimmed")
        #expect(catalog.active(pinned: "Gone", appearance: .dark) == "Default Dark")
    }

    @Test("an unknown theme is refused in words that point at `theme list`")
    func unknown() {
        let catalog = ThemeCatalog(builtIn: [Self.light, Self.dark], user: [])
        #expect(throws: ThemeRefusal.unknown("Purple")) { try catalog.resolve("Purple") }
        #expect(ThemeRefusal.unknown("Purple").line == "no theme Purple; video-review theme list names them")
    }

    @Test("a theme file reads from JSON with its name, kind, optional extends and tokens")
    func decodes() throws {
        let json = ##"{"name": "Brown", "kind": "dark", "extends": "Default Dark", "tokens": {"accent": "#a0522d"}}"##
        let file = try ThemeFile.decode(Data(json.utf8))
        #expect(file == ThemeFile(name: "Brown", kind: .dark, extends: "Default Dark", tokens: ["accent": "#a0522d"]))
        #expect(throws: ThemeFile.Unreadable.self) { try ThemeFile.decode(Data(#"{"name": "X", "kind": "sepia"}"#.utf8)) }
    }
}
