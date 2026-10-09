import Foundation
import TOMLDecoder

/// What `config.toml` sets: the things a person or an agent sets
/// on purpose. App state (recent videos, playheads, the sidebar width,
/// reviews) stays in the support folder.
///
///     #:schema https://raw.githubusercontent.com/yahyabedirhan/havooch/main/schema/config.schema.json
///     version = 1
///     theme = "Dimmed"
///
///     [[projects]]
///     slug = "launch-video"
///     title = "Launch video"
///     versions = [
///       { path = "~/Movies/cut1.mp4" },
///       { path = "~/Movies/cut2.mp4", label = "tighter intro" },
///     ]
///
/// Every key may be left out; a file that sets any key says its
/// `version`. Keys are kebab-case.
public struct ConfigFile: Equatable, Sendable {
    /// The only format version this build reads.
    public static let supportedVersion = 1

    /// The pinned theme, by name; nil follows the Mac's appearance.
    public var theme: String?
    /// The projects, in the file's order.
    public var projects: [ProjectEntry]

    public init(theme: String? = nil, projects: [ProjectEntry] = []) {
        self.theme = theme
        self.projects = projects
    }

    /// Where the published JSON Schema lives. The file's `#:schema` line and
    /// the schema's `$id` are this URL.
    public static let schemaURL = "https://raw.githubusercontent.com/yahyabedirhan/havooch/main/schema/config.schema.json"

    /// The text a new file starts with: the schema line, what the file is,
    /// `version`, and the theme key commented out. Every other key takes
    /// its default.
    public static let header = """
        #:schema \(schemaURL)
        # Havooch settings. The havooch-mate skill explains every key, and
        # `havooch config check` says whether Havooch reads this file.
        # Havooch applies each save at once.
        version = \(supportedVersion)

        # The theme by name, from `havooch theme list`. Leave it out to follow
        # the Mac's light or dark appearance. Your own themes go in themes/
        # beside this file.
        # theme = "Dimmed"

        """

    /// A valid file and the warnings found on the way, such as an unknown key.
    public struct Decoded: Equatable, Sendable {
        public var config: ConfigFile
        public var warnings: [ConfigIssue]

        public init(config: ConfigFile, warnings: [ConfigIssue] = []) {
            self.config = config
            self.warnings = warnings
        }
    }

    /// Reads the bytes of `config.toml`. Empty data is every default.
    public static func decode(_ data: Data) throws(ConfigProblems) -> Decoded {
        guard let text = String(data: data, encoding: .utf8) else {
            throw ConfigProblems([ConfigIssue(line: nil, message: "the file is not UTF-8 text")])
        }
        return try decode(text)
    }

    /// Reads the text of `config.toml`. Empty text, or text with only
    /// comments, is every default.
    ///
    /// Rejects, each with its line: invalid TOML, a value of the wrong type,
    /// a missing or unsupported `version`, an empty `theme`, a project with
    /// no slug, a slug in a wrong form or used twice, a version with no
    /// `path` or a relative one. An unknown key is a warning, so a file
    /// written for a newer Havooch still reads.
    public static func decode(_ text: String) throws(ConfigProblems) -> Decoded {
        let root: TOMLTable
        do {
            root = try TOMLTable(source: text)
        } catch {
            throw ConfigProblems([ConfigIssue(invalidTOML: error)])
        }
        let reader = ConfigReader(map: TOMLSourceMap(text))
        let config = reader.config(from: root)
        if !reader.errors.isEmpty { throw ConfigProblems(reader.errors) }
        return Decoded(config: config, warnings: reader.warnings)
    }
}

/// One thing wrong with the file, on its line when it can be placed.
public struct ConfigIssue: Equatable, Sendable, CustomStringConvertible {
    /// The line in the file, from 1; nil when the issue has no one line.
    public var line: Int?
    public var message: String

    public init(line: Int?, message: String) {
        self.line = line
        self.message = message
    }

    /// `line 4: …`, or the message alone.
    public var description: String {
        line.map { "line \($0): \(message)" } ?? message
    }

    /// TOMLDecoder's parse errors carry the line only in their description,
    /// as "(Line 3) Syntax error: …".
    init(invalidTOML error: any Error) {
        let (line, detail) = Self.splitLine(from: String(describing: error))
        self.init(line: line, message: "invalid TOML: \(detail)")
    }

    static func splitLine(from description: String) -> (Int?, String) {
        guard description.hasPrefix("(Line "),
              let close = description.firstIndex(of: ")"),
              let line = Int(description[description.index(description.startIndex, offsetBy: 6)..<close])
        else { return (nil, description) }
        let rest = description[description.index(after: close)...].trimmingCharacters(in: .whitespaces)
        return (line, rest)
    }
}

/// Why the file doesn't read: each problem, with its line.
public struct ConfigProblems: Error, Equatable, Sendable {
    public var problems: [ConfigIssue]

    public init(_ problems: [ConfigIssue]) {
        self.problems = problems
    }

    /// Every problem on one line, `; ` between them.
    public var line: String {
        problems.map(\.description).joined(separator: "; ")
    }
}
