import Foundation

/// The id of a thread, a message or a send: `<kind>-<hash8>-<n>`, where
/// `hash8` is the first eight hex digits of the video's content hash and `n`
/// a counter of the video's review (`t-f92cbb2a-3`, `m-f92cbb2a-12`,
/// `s-f92cbb2a-1`). A thread's `n` is its number, so `t-f92cbb2a-0` is the
/// General thread. The prefix names the video, so a listener's command works
/// after another video opens.
public struct ItemID: Hashable, Sendable, Codable, CustomStringConvertible {
    public enum Kind: String, Sendable, CaseIterable {
        case thread = "t"
        case message = "m"
        case send = "s"
    }

    public let kind: Kind
    /// The first eight hex digits of the video's content hash.
    public let hash8: String
    /// The counter: a thread's number, or a message's or a send's place in
    /// the order the review made them.
    public let number: Int

    /// The id as it's written: `t-f92cbb2a-3`.
    public var text: String { "\(kind.rawValue)-\(hash8)-\(number)" }

    public init(_ kind: Kind, hash8: String, number: Int) {
        self.kind = kind
        self.hash8 = hash8
        self.number = number
    }

    /// Reads an id as a person or an agent wrote it; nil when it isn't one.
    public init?(_ text: String) {
        let parts = text.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, let kind = Kind(rawValue: String(parts[0])),
              parts[1].count == Self.hashDigits, parts[1].allSatisfy({ $0.isASCII && $0.isHexDigit && !$0.isUppercase }),
              !parts[2].isEmpty, parts[2].allSatisfy({ $0.isASCII && $0.isNumber }),
              parts[2] == "0" || !parts[2].hasPrefix("0"), let number = Int(parts[2])
        else { return nil }
        self.init(kind, hash8: String(parts[1]), number: number)
    }

    /// The `hash8` of the video with `contentHash`: its first eight digits.
    public static func hash8(of contentHash: String) -> String {
        String(contentHash.prefix(hashDigits))
    }

    private static let hashDigits = 8

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

/// A thread's id: `t-<hash8>-<number>`.
public typealias ThreadID = ItemID
/// A message's id: `m-<hash8>-<n>`.
public typealias MessageID = ItemID
/// A send's id: `s-<hash8>-<n>`.
public typealias SendID = ItemID

/// A thread as a command names it: a full thread id, or a bare number of
/// the open video's thread (`0` is General).
public enum ThreadRef: Equatable, Sendable {
    case id(ThreadID)
    case number(Int)

    /// Reads `3` or `t-f92cbb2a-3`; nil when it's neither.
    public init?(_ text: String) {
        if !text.isEmpty, text.allSatisfy({ $0.isASCII && $0.isNumber }), let number = Int(text) {
            self = .number(number)
        } else if let id = ItemID(text), id.kind == .thread {
            self = .id(id)
        } else {
            return nil
        }
    }
}
