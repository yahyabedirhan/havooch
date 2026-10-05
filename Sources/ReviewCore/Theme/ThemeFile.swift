import Foundation

/// Whether a theme is drawn on a light or a dark window. The fallback for a
/// missing token is the default theme of the same kind.
public enum ThemeKind: String, Codable, Sendable, CaseIterable {
    case light, dark
}

/// A theme file as it was written:
///
///     {
///       "name": "Brown",
///       "kind": "dark",
///       "extends": "Default Dark",
///       "tokens": { "accent": "#c08a5b", "window": "#2a2420" }
///     }
///
/// `extends` and `tokens` may be left out. Token names and colours stay as
/// written: `ThemeCatalog.resolve` decides what counts.
public struct ThemeFile: Codable, Equatable, Sendable {
    public var name: String
    public var kind: ThemeKind
    public var extends: String?
    /// Token name to colour text, or `system` for a native surface.
    public var tokens: [String: String]

    public init(name: String, kind: ThemeKind, extends: String? = nil, tokens: [String: String]) {
        self.name = name
        self.kind = kind
        self.extends = extends
        self.tokens = tokens
    }

    private enum CodingKeys: String, CodingKey {
        case name, kind, extends, tokens
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        kind = try container.decode(ThemeKind.self, forKey: .kind)
        extends = try container.decodeIfPresent(String.self, forKey: .extends)
        tokens = try container.decodeIfPresent([String: String].self, forKey: .tokens) ?? [:]
    }

    /// Why a theme file doesn't read, in words.
    public struct Unreadable: Error, Equatable, Sendable {
        public var reason: String

        public init(reason: String) {
            self.reason = reason
        }
    }

    /// Reads a theme file's bytes. A blank name, or a kind other than
    /// `light` or `dark`, doesn't read.
    public static func decode(_ data: Data) throws(Unreadable) -> ThemeFile {
        let file: ThemeFile
        do {
            file = try JSONDecoder().decode(ThemeFile.self, from: data)
        } catch DecodingError.keyNotFound(let key, _) {
            throw Unreadable(reason: "no `\(key.stringValue)`")
        } catch DecodingError.dataCorrupted(let context) where context.codingPath.last?.stringValue == "kind" {
            throw Unreadable(reason: "`kind` is `light` or `dark`")
        } catch {
            throw Unreadable(reason: "not a theme file: \(error.localizedDescription)")
        }
        guard !file.name.trimmingCharacters(in: .whitespaces).isEmpty else { throw Unreadable(reason: "an empty `name`") }
        return file
    }
}
