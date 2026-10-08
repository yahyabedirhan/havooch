import Foundation

/// The verdict on `config.toml` (ADR 0002): whether it reads, and each
/// problem with its line when it does not. `havooch config check` prints
/// it; the app writes it to `config-status.json` in its support folder
/// after each reload, for agents, who edit the file but don't see the app.
/// The same shape as Swift Lab's and Shipyard's.
///
///     {
///       "version": 1,
///       "accepted": false,
///       "checked": "2026-10-08T12:05:01Z",
///       "config": "/Users/me/.config/havooch/config.toml",
///       "configModified": "2026-10-08T12:05:00Z",
///       "problems": [{ "line": 4, "message": "…" }],
///       "warnings": []
///     }
///
/// Times are UTC in whole seconds, so an agent can compare `configModified`
/// with `date -u -r <file> +%Y-%m-%dT%H:%M:%SZ` after its save.
/// `configModified` is null when there is no file, a problem's `line` null
/// when it cannot be placed.
public struct ConfigVerdict: Equatable, Sendable {
    /// The version of the record's format. Adding a field is not a new
    /// version; renaming or changing one is.
    public static let currentVersion = 1
    /// The file the app writes the verdict to, in its support folder: not
    /// beside `config.toml`, whose folder the app watches.
    public static let fileName = "config-status.json"

    /// When the file was read.
    public var checked: Date
    /// The file read.
    public var config: URL
    /// The file's modification time when it was read; nil when there was
    /// no file (every default, accepted).
    public var configModified: Date?
    /// Why the file was rejected; empty when it was accepted.
    public var problems: [ConfigIssue]
    /// What an accepted file has that Havooch ignores, such as an unknown key.
    public var warnings: [ConfigIssue]

    public init(checked: Date, config: URL, configModified: Date?, problems: [ConfigIssue], warnings: [ConfigIssue]) {
        self.checked = checked
        self.config = config
        self.configModified = configModified
        self.problems = problems
        self.warnings = warnings
    }

    public var accepted: Bool { problems.isEmpty }

    /// What `config check` prints: `config.toml reads: <path>` and a line per
    /// warning, or `config.toml doesn't read: <path>` and a line per problem.
    public var lines: String {
        var lines = [accepted ? "config.toml reads: \(config.path)" : "config.toml doesn't read: \(config.path)"]
        lines += problems.map { "  problem, \($0.description)" }
        lines += warnings.map { "  warning, \($0.description)" }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Writes the record to `config-status.json` in `folder`, the app's
    /// support folder, creating the folder when it is missing. The file is
    /// replaced at once, so an agent never reads half of it.
    public func write(in folder: URL) throws(ConfigWriteFailure) {
        let url = folder.appendingPathComponent(Self.fileName, isDirectory: false)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try encoded().write(to: url, options: .atomic)
        } catch {
            throw ConfigWriteFailure("couldn't write the verdict \(url.path): \(error.localizedDescription)")
        }
    }

    /// The record as JSON, keys sorted, ending in a newline.
    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(self)
        data.append(UInt8(ascii: "\n"))
        return data
    }
}

extension ConfigVerdict: Encodable {
    private enum CodingKeys: String, CodingKey {
        case version, accepted, checked, config, configModified, problems, warnings
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.currentVersion, forKey: .version)
        try container.encode(accepted, forKey: .accepted)
        try container.encode(Self.wholeSeconds(checked), forKey: .checked)
        try container.encode(config.path, forKey: .config)
        try container.encode(configModified.map(Self.wholeSeconds), forKey: .configModified)
        try container.encode(problems, forKey: .problems)
        try container.encode(warnings, forKey: .warnings)
    }

    /// `date` in UTC, truncated to the second as `date -r` prints a file's time.
    static func wholeSeconds(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: Date(timeIntervalSince1970: date.timeIntervalSince1970.rounded(.down)))
    }
}

extension ConfigIssue: Encodable {
    private enum CodingKeys: String, CodingKey { case line, message }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        // An explicit null rather than a missing key: easier for an agent to read.
        try container.encode(line, forKey: .line)
        try container.encode(message, forKey: .message)
    }
}

extension ConfigLocation {
    /// Reads and checks the file. A missing file is every default.
    public func read() throws(ConfigProblems) -> ConfigFile.Decoded {
        guard FileManager.default.fileExists(atPath: file.path) else { return ConfigFile.Decoded(config: ConfigFile()) }
        let data: Data
        do {
            data = try Data(contentsOf: file)
        } catch {
            throw ConfigProblems([ConfigIssue(line: nil, message: "can't read \(file.path): \(error.localizedDescription)")])
        }
        return try ConfigFile.decode(data)
    }

    /// The file's modification time; nil when there is no file.
    public var modified: Date? {
        (try? FileManager.default.attributesOfItem(atPath: file.path))?[.modificationDate] as? Date
    }

    /// The file's verdict now, and what it reads as when it reads.
    public func check(at checked: Date = Date()) -> (verdict: ConfigVerdict, decoded: ConfigFile.Decoded?) {
        // Taken before the bytes: a save in between gets a later time, so
        // the verdict never claims a newer file than was read.
        let modified = modified
        do throws(ConfigProblems) {
            let decoded = try read()
            let verdict = ConfigVerdict(checked: checked, config: file, configModified: modified, problems: [], warnings: decoded.warnings)
            return (verdict, decoded)
        } catch {
            return (ConfigVerdict(checked: checked, config: file, configModified: modified, problems: error.problems, warnings: []), nil)
        }
    }
}
