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
        let base = ThemeFile(name: "Base", kind: .dark, tokens: ["accent": "#111111", "letterbox": "#222222"])
        let child = ThemeFile(name: "Child", kind: .dark, extends: "Base", tokens: ["accent": "#333333"])
        let catalog = ThemeCatalog(builtIn: [Self.light, Self.dark], user: [base, child])

        let theme = try catalog.resolve("Child")
        #expect(theme.name == "Child")
        #expect(theme.kind == .dark)
        #expect(theme[.accent] == Self.colour("#333333"))
        #expect(theme[.letterbox] == Self.colour("#222222"))
        #expect(theme[.window] == Self.colour("#000000"))
        #expect(theme.isComplete)
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
            ThemeCatalog.defaultDark, overrides: ["accent": "#abcdef", "nonsense": "#ffffff", "letterbox": "blue"]
        )
        #expect(theme[.accent] == Self.colour("#abcdef"))
        #expect(theme[.letterbox] == Self.colour("#000000"))
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
        #expect(theme[.letterbox] == Self.colour("#000000"))
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
        #expect(ThemeRefusal.unknown("Purple").line == "no theme Purple; havooch theme list names them")
    }

    @Test("a theme file reads from JSON with its name, kind, optional extends and tokens")
    func decodes() throws {
        let json = ##"{"name": "Brown", "kind": "dark", "extends": "Default Dark", "tokens": {"accent": "#a0522d"}}"##
        let file = try ThemeFile.decode(Data(json.utf8))
        #expect(file == ThemeFile(name: "Brown", kind: .dark, extends: "Default Dark", tokens: ["accent": "#a0522d"]))
        #expect(throws: ThemeFile.Unreadable.self) { try ThemeFile.decode(Data(#"{"name": "X", "kind": "sepia"}"#.utf8)) }
    }

    // MARK: - System surfaces

    /// A light default with its surfaces set to `system` and every other
    /// token painted white.
    private static let nativeLight = ThemeFile(
        name: ThemeCatalog.defaultLight, kind: .light,
        tokens: Dictionary(uniqueKeysWithValues: ThemeToken.allCases.map {
            ($0.rawValue, ThemeToken.systemSurfaces.contains($0) ? ThemeCatalog.system : "#ffffff")
        })
    )

    @Test("a surface token set to system resolves to the native part, with no painted colour, and the theme is still complete")
    func systemValue() throws {
        let catalog = ThemeCatalog(builtIn: [Self.nativeLight, Self.dark], user: [])
        let theme = try catalog.resolve(ThemeCatalog.defaultLight)
        #expect(theme.system == ThemeToken.systemSurfaces)
        for token in ThemeToken.systemSurfaces {
            #expect(theme.isSystem(token))
            #expect(theme[token] == nil)
        }
        #expect(!theme.isSystem(.accent))
        #expect(theme[.accent] == Self.colour("#ffffff"))
        #expect(theme.isComplete)
    }

    @Test("a painted value wins over a system one it extends, and a missing one takes system from the default of its kind")
    func paintedAndMissingBesideSystem() throws {
        let paper = ThemeFile(name: "Paper", kind: .light, tokens: ["window": "#fafafa", "popover": "#eeeeee"])
        let catalog = ThemeCatalog(builtIn: [Self.nativeLight, Self.dark], user: [paper])
        let theme = try catalog.resolve("Paper")
        // Painted.
        #expect(theme[.window] == Self.colour("#fafafa"))
        #expect(!theme.isSystem(.window))
        #expect(!theme.isSystem(.popover))
        // Missing: the default's system value.
        #expect(theme.isSystem(.notice))
        #expect(theme[.notice] == nil)
        #expect(theme.isComplete)
    }

    @Test("system on a token that is not a surface counts as missing, as a colour that doesn't read does")
    func systemOnlyOnSurfaces() throws {
        let odd = ThemeFile(name: "Odd", kind: .light, tokens: ["accent": "system", "textPrimary": "System", "window": "system"])
        let catalog = ThemeCatalog(builtIn: [Self.light, Self.dark], user: [odd])
        let theme = try catalog.resolve("Odd")
        #expect(theme.system == [.window])
        #expect(theme[.accent] == Self.colour("#ffffff"))
        #expect(theme[.textPrimary] == Self.colour("#ffffff"))
        #expect(ThemeCatalog.reads("system", for: .popover))
        #expect(!ThemeCatalog.reads("system", for: .accent))
        #expect(ThemeCatalog.reads("#123456", for: .accent))
        #expect(!ThemeCatalog.reads("blue", for: .window))
    }

    @Test("an override can set a surface to system or paint a system one")
    func overridesAndSystem() throws {
        let catalog = ThemeCatalog(builtIn: [Self.nativeLight, Self.dark], user: [])
        let painted = try catalog.resolve(ThemeCatalog.defaultLight, overrides: ["window": "#101010", "accent": "system"])
        #expect(painted[.window] == Self.colour("#101010"))
        #expect(!painted.isSystem(.window))
        #expect(painted[.accent] == Self.colour("#ffffff"))
        #expect(painted.isComplete)

        let native = try catalog.resolve(ThemeCatalog.defaultDark, overrides: ["field": "system"])
        #expect(native.system == [.field])
        #expect(native[.field] == nil)
        #expect(native.isComplete)
    }

    // MARK: - The fill of filled controls

    @Test("the contrast of two colours is the WCAG ratio: white on black is 21:1, white on #48689d about 5.6:1")
    func contrast() {
        #expect(ThemeColor.white.contrast(with: Self.colour("#000000")) == 21)
        #expect(abs(ThemeColor.white.contrast(with: Self.colour("#48689d")) - 5.61) < 0.01)
        #expect(Self.colour("#48689d").contrast(with: .white) == ThemeColor.white.contrast(with: Self.colour("#48689d")))
    }

    @Test("a colour white text already reads on fills as itself, opaque; a light one is darkened, its hue kept, until white text reads at 4.5:1")
    func filled() {
        #expect(Self.colour("#48689d80").filled() == Self.colour("#48689d"))
        for light in ["#9db6dd", "#cba6f7", "#ffffff", "#fff176"] {
            let fill = Self.colour(light).filled()
            #expect(fill.contrast(with: .white) >= ThemeColor.filledTextContrast, "\(light) fills as \(fill.text)")
            #expect(fill.contrast(with: .white) < ThemeColor.filledTextContrast + 0.3, "\(light) fills as \(fill.text), darker than it needs")
        }
        let fill = Self.colour("#9db6dd").filled()
        #expect(fill.blue > fill.green && fill.green > fill.red, "the fill of a blue stays blue: \(fill.text)")
    }

    @Test("a theme without accentFill takes it from the theme it extends, or the default of its kind, while it doesn't set its own accent")
    func fillFallsBack() throws {
        let base = ThemeFile(name: "Base", kind: .dark, tokens: ["accent": "#9db6dd", "accentFill": "#48689d"])
        let child = ThemeFile(name: "Child", kind: .dark, extends: "Base", tokens: ["letterbox": "#111111"])
        let plain = ThemeFile(name: "Plain", kind: .dark, tokens: [:])
        let catalog = ThemeCatalog(builtIn: [Self.light, Self.dark], user: [base, child, plain])

        #expect(try catalog.resolve("Child")[.accentFill] == Self.colour("#48689d"))
        #expect(try catalog.resolve("Plain")[.accentFill] == Self.colour("#000000"))
    }

    @Test("a theme that sets its own accent and no accentFill gets a fill made from that accent, not the fallback's fill in another hue")
    func fillFollowsTheAccent() throws {
        let brown = ThemeFile(name: "Brown", kind: .dark, extends: ThemeCatalog.defaultDark, tokens: ["accent": "#d2a07a"])
        let both = ThemeFile(name: "Both", kind: .dark, tokens: ["accent": "#d2a07a", "accentFill": "#5a3b22"])
        let child = ThemeFile(name: "Child", kind: .dark, extends: "Both", tokens: ["accent": "#9db6dd"])
        let catalog = ThemeCatalog(builtIn: [Self.light, Self.dark], user: [brown, both, child])

        let fill = try #require(try catalog.resolve("Brown")[.accentFill])
        #expect(fill == Self.colour("#d2a07a").filled())
        #expect(fill.contrast(with: .white) >= ThemeColor.filledTextContrast)
        #expect(try catalog.resolve("Both")[.accentFill] == Self.colour("#5a3b22"))
        #expect(try catalog.resolve("Child")[.accentFill] == Self.colour("#9db6dd").filled())
    }

    @Test("an accent override makes the fill from it; an accentFill override wins over both")
    func fillAndOverrides() throws {
        let both = ThemeFile(name: "Both", kind: .dark, tokens: ["accent": "#d2a07a", "accentFill": "#5a3b22"])
        let catalog = ThemeCatalog(builtIn: [Self.light, Self.dark], user: [both])

        #expect(try catalog.resolve("Both", overrides: ["accent": "#9db6dd"])[.accentFill] == Self.colour("#9db6dd").filled())
        #expect(try catalog.resolve("Both", overrides: ["accent": "#9db6dd", "accentFill": "#123456"])[.accentFill] == Self.colour("#123456"))
        #expect(try catalog.resolve("Both", overrides: ["letterbox": "#101010"])[.accentFill] == Self.colour("#5a3b22"))
    }
}
