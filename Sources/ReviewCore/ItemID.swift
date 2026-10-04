import Foundation

/// The id of a comment, a batch or a thread message: a prefix that names the
/// kind, then 8 random hex digits (`c-7f3a9c2e`). Ids are unique across
/// videos, so a command names an item without naming its video.
public struct ItemID: Hashable, Sendable, Codable, CustomStringConvertible {
    public enum Kind: String, Sendable, CaseIterable {
        case comment = "c"
        case batch = "b"
        case message = "m"
    }

    /// The id as it's written: `c-7f3a9c2e`.
    public let text: String
    public let kind: Kind

    /// Reads an id as a person or an agent wrote it; nil when it isn't one.
    public init?(_ text: String) {
        let parts = text.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 2, let kind = Kind(rawValue: String(parts[0])), parts[1].count == Self.digits,
              parts[1].allSatisfy({ $0.isASCII && $0.isHexDigit && !$0.isUppercase })
        else { return nil }
        self.text = text
        self.kind = kind
    }

    /// A new id of `kind`.
    public static func make(_ kind: Kind) -> ItemID {
        var generator = SystemRandomNumberGenerator()
        return make(kind, using: &generator)
    }

    /// A new id of `kind` from `generator`, so a test names its ids.
    public static func make(_ kind: Kind, using generator: inout some RandomNumberGenerator) -> ItemID {
        let value = UInt32.random(in: .min ... .max, using: &generator)
        let hex = String(value, radix: 16)
        // The shape is right by construction.
        return ItemID("\(kind.rawValue)-\(String(repeating: "0", count: digits - hex.count))\(hex)")!
    }

    private static let digits = 8

    public var description: String { text }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard let id = ItemID(text) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "`\(text)` isn't an item id")
        }
        self = id
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(text)
    }
}
