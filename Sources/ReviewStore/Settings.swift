import Foundation

/// The person's settings, kept in `settings.json` in the support folder:
///
///     {
///       "overrides": { "accent": "#c08a5b" },
///       "sidebarWidth": 360,
///       "theme": "Dimmed"
///     }
///
/// `theme` is the pinned theme; `null` follows the system appearance.
/// `overrides` maps a token name to a colour, applied on top of the active
/// theme. The person may edit the file by hand: every key may be left out.
public struct Settings: Codable, Equatable, Sendable {
    public var theme: String?
    public var overrides: [String: String]
    public var sidebarWidth: Double?

    public init(theme: String? = nil, overrides: [String: String] = [:], sidebarWidth: Double? = nil) {
        self.theme = theme
        self.overrides = overrides
        self.sidebarWidth = sidebarWidth
    }

    private enum CodingKeys: String, CodingKey {
        case theme, overrides, sidebarWidth
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        theme = try container.decodeIfPresent(String.self, forKey: .theme)
        overrides = try container.decodeIfPresent([String: String].self, forKey: .overrides) ?? [:]
        sidebarWidth = try container.decodeIfPresent(Double.self, forKey: .sidebarWidth)
    }

    /// `theme` is written as `null` while it follows the system, so the
    /// person sees the key to set.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(theme, forKey: .theme)
        try container.encode(overrides, forKey: .overrides)
        try container.encodeIfPresent(sidebarWidth, forKey: .sidebarWidth)
    }

    /// The settings in `layout`'s `settings.json`; the defaults when there
    /// is no file. Throws when there is one and it doesn't read: it must
    /// not be written over.
    public static func load(_ layout: SupportLayout) throws(Library.Failure) -> Settings {
        let file = layout.settingsFile
        guard FileManager.default.fileExists(atPath: file.path) else { return Settings() }
        do {
            return try JSONDecoder().decode(Settings.self, from: try Data(contentsOf: file))
        } catch {
            throw Library.Failure(reason: "\(file.path) doesn't read (\(error.localizedDescription)); it's left as it is")
        }
    }

    /// Writes the settings to `layout`'s `settings.json`, atomically.
    public func save(_ layout: SupportLayout) throws(Library.Failure) {
        let file = layout.settingsFile
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            try FileManager.default.createDirectory(at: layout.root, withIntermediateDirectories: true)
            try encoder.encode(self).write(to: file, options: .atomic)
        } catch {
            throw Library.Failure(reason: "couldn't write \(file.path): \(error.localizedDescription)")
        }
    }
}
