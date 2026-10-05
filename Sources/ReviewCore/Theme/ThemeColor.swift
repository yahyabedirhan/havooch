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
