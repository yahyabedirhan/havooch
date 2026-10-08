import Foundation

/// A theme with every token it could resolve.
public struct ResolvedTheme: Equatable, Sendable {
    public var name: String
    public var kind: ThemeKind
    /// The tokens with a painted colour. With `system`, every token,
    /// unless no theme in its chain nor its kind's default sets it (a
    /// catalog without the default themes).
    public var colors: [ThemeToken: ThemeColor]
    /// The tokens set to `system`: the app draws the native macOS part
    /// for each. Only `ThemeToken.systemSurfaces` can be here.
    public var system: Set<ThemeToken>

    public init(name: String, kind: ThemeKind, colors: [ThemeToken: ThemeColor], system: Set<ThemeToken> = []) {
        self.name = name
        self.kind = kind
        self.colors = colors
        self.system = system
    }

    /// The painted colour of `token`; nil for a `system` token and a
    /// missing one.
    public subscript(_ token: ThemeToken) -> ThemeColor? {
        colors[token]
    }

    /// Whether `token` is the native macOS part, not a painted colour.
    public func isSystem(_ token: ThemeToken) -> Bool {
        system.contains(token)
    }

    /// Whether every token has a value, painted or `system`.
    public var isComplete: Bool {
        colors.count + system.count == ThemeToken.allCases.count
    }
}

/// Why a theme can't be used.
public enum ThemeRefusal: Error, Equatable, Sendable {
    /// No theme in the catalog has the name.
    case unknown(String)

    /// The refusal as the one line the command prints.
    public var line: String {
        switch self {
        case .unknown(let name): "no theme \(name); havooch theme list names them"
        }
    }
}

/// The themes the app knows, and how a theme resolves to every token.
///
/// A theme's token comes from the first of: the theme itself, the themes
/// up its `extends` chain, the default theme of its kind (`Default Light`
/// or `Default Dark`). Overrides apply on top. A token name the app doesn't
/// know is ignored, and a colour that doesn't read counts as missing. A
/// surface token may be `system` (`ThemeCatalog.system`) in place of a
/// colour: the native macOS part; on any other token `system` counts as
/// missing. One exception: a theme that sets `accent` nearer than
/// `accentFill` (itself, a theme it extends, or an override) gets
/// `accentFill` made from that accent (`ThemeColor.filled()`), so its
/// filled buttons keep its hue and white text still reads on them.
/// A pure value: the files are read by the store.
public struct ThemeCatalog: Equatable, Sendable {
    public static let defaultLight = "Default Light"
    public static let defaultDark = "Default Dark"
    /// The value that makes a surface token the native macOS part.
    public static let system = "system"

    /// Where a theme comes from.
    public enum Source: String, Equatable, Sendable {
        /// Shipped in the app bundle.
        case builtIn = "built-in"
        /// A file in the support folder's `Themes/`.
        case user
    }

    public struct Entry: Equatable, Sendable {
        public var file: ThemeFile
        public var source: Source

        public var name: String { file.name }
    }

    /// The themes that can be used, by name.
    public private(set) var entries: [Entry]
    /// The themes left out, each with its reason, as a line.
    public private(set) var problems: [String] = []
    /// The built-in default themes, the last fallback even when a user
    /// theme replaces one of them.
    private var builtInDefaults: [ThemeKind: ThemeFile] = [:]

    /// `user` themes replace the `builtIn` ones of the same name (without
    /// regard to case); of two user themes with one name, the later one
    /// wins. A theme whose `extends` names no theme, or loops back, is
    /// left out with its reason in `problems`.
    public init(builtIn: [ThemeFile], user: [ThemeFile]) {
        var byKey: [String: Entry] = [:]
        for file in builtIn { byKey[Self.key(file.name)] = Entry(file: file, source: .builtIn) }
        for kind in ThemeKind.allCases {
            builtInDefaults[kind] = builtIn.last { Self.key($0.name) == Self.key(Self.defaultName(of: kind)) }
        }
        for file in user { byKey[Self.key(file.name)] = Entry(file: file, source: .user) }
        entries = []
        for entry in byKey.values {
            do throws(Broken) {
                _ = try Self.chain(of: entry, in: byKey)
                entries.append(entry)
            } catch {
                problems.append("theme \(entry.name) is left out: \(error.reason)")
            }
        }
        entries.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        problems.sort()
    }

    /// The names of the themes that can be used, in order.
    public var names: [String] { entries.map(\.name) }

    /// The theme called `name`, without regard to case.
    public func entry(named name: String) -> Entry? {
        entries.first { Self.key($0.name) == Self.key(name) }
    }

    /// The theme called `name` with every token resolved and `overrides`
    /// (token name to colour text) on top.
    public func resolve(_ name: String, overrides: [String: String] = [:]) throws(ThemeRefusal) -> ResolvedTheme {
        guard let entry = entry(named: name) else { throw .unknown(name) }
        let byKey = Dictionary(uniqueKeysWithValues: entries.map { (Self.key($0.name), $0) })
        // The catalog only keeps themes whose chain resolves.
        var files = ((try? Self.chain(of: entry, in: byKey)) ?? [entry]).map(\.file)
        if let base = byKey[Self.key(Self.defaultName(of: entry.file.kind))], let baseChain = try? Self.chain(of: base, in: byKey) {
            files += baseChain.map(\.file)
        }
        if let builtIn = builtInDefaults[entry.file.kind] { files.append(builtIn) }
        var colors: [ThemeToken: ThemeColor] = [:]
        var system: Set<ThemeToken> = []
        func set(_ token: ThemeToken, _ value: Value) {
            switch value {
            case .painted(let color):
                colors[token] = color
                system.remove(token)
            case .system:
                colors[token] = nil
                system.insert(token)
            }
        }
        // Where each token's value came from: its file's place in `files`.
        var source: [ThemeToken: Int] = [:]
        for token in ThemeToken.allCases {
            for (index, file) in files.enumerated() {
                guard let value = file.tokens[token.rawValue].flatMap({ Value($0, for: token) }) else { continue }
                set(token, value)
                source[token] = index
                break
            }
        }
        var overridden: Set<ThemeToken> = []
        for (name, text) in overrides {
            guard let token = ThemeToken(rawValue: name), let value = Value(text, for: token) else { continue }
            set(token, value)
            overridden.insert(token)
        }
        // The fill follows the theme's own accent: a theme (or an override)
        // that sets `accent` nearer than `accentFill` gets a fill made
        // from that accent, not the fallback's fill in another hue.
        let accentIsNearer = if overridden.contains(.accentFill) {
            false
        } else if overridden.contains(.accent) {
            true
        } else {
            (source[.accent] ?? .max) < (source[.accentFill] ?? .max)
        }
        if accentIsNearer, let accent = colors[.accent] {
            colors[.accentFill] = accent.filled()
        }
        return ResolvedTheme(name: entry.name, kind: entry.file.kind, colors: colors, system: system)
    }

    /// What a token's text in a theme file counts as.
    private enum Value {
        case painted(ThemeColor)
        case system

        /// A colour that reads, or `system` on a surface token; nil
        /// (missing) for anything else.
        init?(_ text: String, for token: ThemeToken) {
            if text == ThemeCatalog.system {
                guard ThemeToken.systemSurfaces.contains(token) else { return nil }
                self = .system
            } else if let color = ThemeColor(text) {
                self = .painted(color)
            } else {
                return nil
            }
        }
    }

    /// Whether `text` is a value `token` takes: a colour that reads, or
    /// `system` on a surface token.
    public static func reads(_ text: String, for token: ThemeToken) -> Bool {
        Value(text, for: token) != nil
    }

    /// The name of the theme the app shows: the pinned one while it
    /// exists, else the default of the system's `appearance`.
    public func active(pinned: String?, appearance: ThemeKind) -> String {
        if let pinned, let entry = entry(named: pinned) { return entry.name }
        return Self.defaultName(of: appearance)
    }

    /// `Default Light` or `Default Dark`.
    public static func defaultName(of kind: ThemeKind) -> String {
        kind == .light ? defaultLight : defaultDark
    }

    // MARK: - The chain

    private struct Broken: Error {
        var reason: String
    }

    /// `entry`, then each theme it extends, in order.
    private static func chain(of entry: Entry, in byKey: [String: Entry]) throws(Broken) -> [Entry] {
        var chain = [entry]
        var seen: Set<String> = [key(entry.name)]
        var current = entry
        while let parent = current.file.extends {
            guard let next = byKey[key(parent)] else {
                throw Broken(reason: "\(current.name) extends \(parent), and no theme has that name")
            }
            guard seen.insert(key(next.name)).inserted else {
                throw Broken(reason: "its `extends` loops back to \(next.name)")
            }
            chain.append(next)
            current = next
        }
        return chain
    }

    private static func key(_ name: String) -> String {
        name.lowercased()
    }
}
