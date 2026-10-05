import AppKit
@testable import ReviewApp
import ReviewCore
import ReviewStore
import Testing

/// The palette as the views see it: a `system` surface is the native macOS
/// colour, a painted one its theme colour, and in every shipped theme the
/// text reads on each surface as the window draws it.
@Suite("The palette")
struct PaletteTests {
    /// `Packaging/Themes/`, which `make bundle` copies into the app.
    static let shipped = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Packaging/Themes", isDirectory: true)

    static let catalog = ThemeCatalog(builtIn: ThemeFiles.read(shipped).files, user: [])

    @Test("a system surface is the native colour: the window background, a text field's background, the separator; a painted one is its theme colour")
    func systemColours() throws {
        let native = Palette(theme: try Self.catalog.resolve(ThemeCatalog.defaultLight))
        #expect(native.isNative)
        #expect(native.nsColor(.window) == .windowBackgroundColor)
        #expect(native.nsColor(.popover) == .windowBackgroundColor)
        #expect(native.nsColor(.notice) == .windowBackgroundColor)
        #expect(native.nsColor(.field) == .textBackgroundColor)
        #expect(native.nsColor(.separator) == .separatorColor)

        let painted = Palette(theme: try Self.catalog.resolve("Tokyo Night"))
        #expect(!painted.isNative)
        let window = try #require(painted.theme[.window])
        #expect(Self.components(painted.nsColor(.window), kind: .dark) == Self.components(window))
    }

    @Test("in every shipped theme the text reads on each surface as the window draws it, and each state stands apart from the surfaces, its glyph and the other states, and the question from every state and the window")
    func everyThemeReads() throws {
        let states: [ThemeToken] = [.stateQueued, .stateSent, .stateAcknowledged, .stateWorking, .stateDone, .stateFailed]
        for name in Self.catalog.names {
            let palette = Palette(theme: try Self.catalog.resolve(name))
            func colour(_ token: ThemeToken) -> RGB { Self.components(palette.nsColor(token), kind: palette.theme.kind) }
            for surface: ThemeToken in [.window, .popover, .field] {
                let primary = Self.contrast(colour(.textPrimary), colour(surface))
                let secondary = Self.contrast(colour(.textSecondary), colour(surface))
                #expect(primary >= 6, "\(name): textPrimary on \(surface) is \(primary):1")
                #expect(secondary >= 4.5, "\(name): textSecondary on \(surface) is \(secondary):1")
            }
            let notice = Self.contrast(colour(.noticeText), colour(.notice))
            #expect(notice >= 6, "\(name): noticeText on notice is \(notice):1")
            for token in states + [.accent, .question] {
                for surface: ThemeToken in [.window, .popover] {
                    let ratio = Self.contrast(colour(token), colour(surface))
                    #expect(ratio >= 2.5, "\(name): \(token) on \(surface) is \(ratio):1")
                }
                let glyph = Self.contrast(colour(.textOnAccent), colour(token))
                #expect(glyph >= 3, "\(name): textOnAccent on \(token) is \(glyph):1")
            }
            // The question's pin on the player bar stands apart from every
            // state's pin, and shows on the window's surface as a mark should (3:1).
            let questionOnWindow = Self.contrast(colour(.question), colour(.window))
            #expect(questionOnWindow >= 3, "\(name): question on window is \(questionOnWindow):1")
            for state in states {
                let distance = Self.distance(colour(.question), colour(state))
                #expect(distance >= 10, "\(name): question and \(state) are \(distance) apart")
            }
            for (index, one) in states.enumerated() {
                for other in states[(index + 1)...] {
                    let distance = Self.distance(colour(one), colour(other))
                    #expect(distance >= 10, "\(name): \(one) and \(other) are \(distance) apart")
                }
            }
        }
    }

    // MARK: - Colour arithmetic

    /// sRGB components, 0 to 1.
    struct RGB: Equatable {
        var red, green, blue: Double
    }

    /// `color` in sRGB as a window of `kind` draws it: a system colour
    /// resolves in that appearance.
    static func components(_ color: NSColor, kind: ThemeKind) -> RGB {
        var rgb = RGB(red: 0, green: 0, blue: 0)
        NSAppearance(named: kind == .dark ? .darkAqua : .aqua)?.performAsCurrentDrawingAppearance {
            guard let converted = color.usingColorSpace(.sRGB) else { return }
            rgb = RGB(red: converted.redComponent, green: converted.greenComponent, blue: converted.blueComponent)
        }
        return rgb
    }

    static func components(_ color: ThemeColor) -> RGB {
        RGB(red: Double(color.red) / 255, green: Double(color.green) / 255, blue: Double(color.blue) / 255)
    }

    /// The WCAG contrast ratio of two opaque colours, from 1 to 21.
    static func contrast(_ one: RGB, _ other: RGB) -> Double {
        let (a, b) = (luminance(one), luminance(other))
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    private static func linear(_ c: Double) -> Double {
        c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }

    private static func luminance(_ color: RGB) -> Double {
        0.2126 * linear(color.red) + 0.7152 * linear(color.green) + 0.0722 * linear(color.blue)
    }

    /// How far apart two colours look: the CIE76 distance in CIELAB.
    static func distance(_ one: RGB, _ other: RGB) -> Double {
        let (a, b) = (lab(one), lab(other))
        return ((a.0 - b.0) * (a.0 - b.0) + (a.1 - b.1) * (a.1 - b.1) + (a.2 - b.2) * (a.2 - b.2)).squareRoot()
    }

    private static func lab(_ color: RGB) -> (Double, Double, Double) {
        let (r, g, b) = (linear(color.red), linear(color.green), linear(color.blue))
        let x = (0.4124 * r + 0.3576 * g + 0.1805 * b) / 0.95047
        let y = 0.2126 * r + 0.7152 * g + 0.0722 * b
        let z = (0.0193 * r + 0.1192 * g + 0.9505 * b) / 1.08883
        func f(_ t: Double) -> Double { t > 0.008856 ? cbrt(t) : 7.787 * t + 16.0 / 116 }
        return (116 * f(y) - 16, 500 * (f(x) - f(y)), 200 * (f(y) - f(z)))
    }
}
