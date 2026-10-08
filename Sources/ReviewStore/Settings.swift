import Foundation

/// App state the window keeps between runs, in `settings.json` in the
/// support folder:
///
///     { "agentConnectedOnce": true, "firstRunDone": true, "sidebarWidth": 360, "unmuteVolume": 0.7, "volume": 0 }
///
/// Not settings a person sets on purpose: those are in `config.toml`
/// (ADR 0002). Builds before it kept the pinned theme and token overrides
/// here too; `Former` reads them once, for the move into `config.toml`, and
/// the next save leaves them out.
public struct Settings: Codable, Equatable, Sendable {
    public var sidebarWidth: Double?
    /// Whether an agent's `wait` ever opened on this data: the connect
    /// button's dot leaves for good once one has (L57).
    public var agentConnectedOnce: Bool?
    /// Whether the person used the app on this data: Get Started or a
    /// later step, Skip Setup, a video opened or an agent connected. Until
    /// then the first-run window shows by itself at each launch (L65).
    public var firstRunDone: Bool?
    /// The sound's level, 0 to 1, the same in every window; 0 is muted
    ///. Missing is full volume.
    public var volume: Double?
    /// The level unmute brings back: the last one above 0.
    public var unmuteVolume: Double?

    public init(
        sidebarWidth: Double? = nil, agentConnectedOnce: Bool? = nil, firstRunDone: Bool? = nil, volume: Double? = nil,
        unmuteVolume: Double? = nil
    ) {
        self.sidebarWidth = sidebarWidth
        self.agentConnectedOnce = agentConnectedOnce
        self.firstRunDone = firstRunDone
        self.volume = volume
        self.unmuteVolume = unmuteVolume
    }

    /// What builds before `config.toml` kept in `settings.json`: the pinned
    /// theme (`null` followed the system) and the token overrides.
    public struct Former: Equatable, Sendable {
        public var theme: String?
        public var overrides: [String: String]

        public init(theme: String? = nil, overrides: [String: String] = [:]) {
            self.theme = theme
            self.overrides = overrides
        }
    }

    private struct FormerKeys: Decodable {
        var theme: String??
        var overrides: [String: String]?

        private enum CodingKeys: String, CodingKey { case theme, overrides }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            // Present as null is not absent: the file still has the key to retire.
            theme = container.contains(.theme) ? .some(try container.decodeIfPresent(String.self, forKey: .theme)) : nil
            overrides = try container.decodeIfPresent([String: String].self, forKey: .overrides)
        }
    }

    /// The settings in `layout`'s `settings.json`; the defaults when there
    /// is no file. Throws when there is one and it doesn't read: it must
    /// not be written over.
    public static func load(_ layout: SupportLayout) throws(Library.Failure) -> Settings {
        guard let data = try read(layout) else { return Settings() }
        do {
            return try JSONDecoder().decode(Settings.self, from: data)
        } catch {
            throw Library.Failure(reason: "\(layout.settingsFile.path) doesn't read (\(error.localizedDescription)); it's left as it is")
        }
    }

    /// The theme and the overrides an older build left in `layout`'s
    /// `settings.json`; nil when it has neither key, or there is no file.
    /// Throws when the file doesn't read.
    public static func former(_ layout: SupportLayout) throws(Library.Failure) -> Former? {
        guard let data = try read(layout) else { return nil }
        let keys: FormerKeys
        do {
            keys = try JSONDecoder().decode(FormerKeys.self, from: data)
        } catch {
            throw Library.Failure(reason: "\(layout.settingsFile.path) doesn't read (\(error.localizedDescription)); it's left as it is")
        }
        guard keys.theme != nil || keys.overrides != nil else { return nil }
        return Former(theme: keys.theme ?? nil, overrides: keys.overrides ?? [:])
    }

    private static func read(_ layout: SupportLayout) throws(Library.Failure) -> Data? {
        let file = layout.settingsFile
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        do {
            return try Data(contentsOf: file)
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
