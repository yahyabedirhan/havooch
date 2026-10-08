import Foundation

/// One colour of a theme, as a theme file writes it: `#rrggbb`, or
/// `#rrggbbaa` with its opacity. Components are 0 to 255, in sRGB.
public struct ThemeColor: Equatable, Hashable, Sendable {
    public var red: UInt8
    public var green: UInt8
    public var blue: UInt8
    public var alpha: UInt8

    public init(red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8 = 255) {
        (self.red, self.green, self.blue, self.alpha) = (red, green, blue, alpha)
    }

    /// Reads `#rrggbb` or `#rrggbbaa`, in either case; nil for anything else.
    public init?(_ text: String) {
        guard text.first == "#" else { return nil }
        let digits = text.dropFirst()
        guard digits.count == 6 || digits.count == 8, digits.allSatisfy(\.isHexDigit),
              let value = UInt32(digits, radix: 16)
        else { return nil }
        let full = digits.count == 6 ? value << 8 | 0xFF : value
        self.init(
            red: UInt8(full >> 24 & 0xFF), green: UInt8(full >> 16 & 0xFF), blue: UInt8(full >> 8 & 0xFF),
            alpha: UInt8(full & 0xFF)
        )
    }

    /// `#rrggbb`, or `#rrggbbaa` when it isn't opaque, in lower case.
    public var text: String {
        let parts = alpha == 255 ? [red, green, blue] : [red, green, blue, alpha]
        return "#" + parts.map { byte in
            let hex = String(byte, radix: 16)
            return hex.count == 1 ? "0" + hex : hex
        }.joined()
    }
}

// MARK: - Contrast

extension ThemeColor {
    public static let white = ThemeColor(red: 255, green: 255, blue: 255)

    /// The least WCAG contrast white text keeps on a filled control:
    /// `accentFill` in every theme.
    public static let filledTextContrast = 4.5

    /// The WCAG relative luminance, 0 (black) to 1 (white). The opacity
    /// is left out.
    public var luminance: Double {
        func linear(_ byte: UInt8) -> Double {
            let c = Double(byte) / 255
            return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    /// The WCAG contrast ratio with `other`, 1 to 21, both taken as opaque.
    public func contrast(with other: ThemeColor) -> Double {
        let (a, b) = (luminance, other.luminance)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    /// The colour as the fill of a filled control: itself when white text
    /// reads on it at `filledTextContrast`, else itself darkened in steps
    /// of 1%, its hue kept, until white text does. Always opaque.
    public func filled() -> ThemeColor {
        let opaque = ThemeColor(red: red, green: green, blue: blue)
        for step in 0...100 {
            let factor = 1 - Double(step) / 100
            func scaled(_ byte: UInt8) -> UInt8 { UInt8((Double(byte) * factor).rounded()) }
            let candidate = ThemeColor(red: scaled(opaque.red), green: scaled(opaque.green), blue: scaled(opaque.blue))
            if candidate.contrast(with: .white) >= Self.filledTextContrast { return candidate }
        }
        return ThemeColor(red: 0, green: 0, blue: 0)
    }
}
