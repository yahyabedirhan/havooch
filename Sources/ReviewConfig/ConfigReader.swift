import Foundation
import TOMLDecoder

// After Swift Lab's reader (yahyabedirhan/swift-lab at ccb82cb,
// `Sources/LabConfig/ConfigurationReader.swift`), itself after Shipyard's:
// TOMLDecoder parses the text, this walks it key by key, and
// `TOMLSourceMap` places each problem on its line.

/// Walks the parsed file key by key, filling a `ConfigFile`, collecting
/// errors (which reject the file) and warnings (which do not).
final class ConfigReader {
    private let map: TOMLSourceMap
    private(set) var errors: [ConfigIssue] = []
    private(set) var warnings: [ConfigIssue] = []

    /// The keys at the top of the file, which the schema lists too.
    static let topKeys = ["version", "theme", "projects"]
    static let projectKeys = ["slug", "title", "versions"]
    static let versionKeys = ["path", "label"]

    init(map: TOMLSourceMap) { self.map = map }

    /// A table and where it sits in the file.
    struct Node {
        let table: TOMLTable
        let path: ConfigPath
    }

    // MARK: The file's shape

    func config(from root: TOMLTable) -> ConfigFile {
        let node = Node(table: root, path: [])
        var config = ConfigFile()
        warnUnknownKeys(in: node, known: Self.topKeys)

        if let version = int(node, "version") {
            if version != ConfigFile.supportedVersion {
                error(
                    "`version` \(version) is not supported; this Havooch reads version \(ConfigFile.supportedVersion)",
                    at: [.key("version")]
                )
            }
        } else if !node.table.keys.isEmpty, !node.table.contains(key: "version") {
            // An empty file is every default; a written one says its version.
            errors.append(ConfigIssue(
                line: map.entries.first?.line,
                message: "the file needs `version = \(ConfigFile.supportedVersion)` at its top"
            ))
        }

        if let theme = string(node, "theme") {
            if theme.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                error("`theme` is empty; leave it out to follow the Mac's appearance", at: [.key("theme")])
            } else {
                config.theme = theme
            }
        }

        if let projects = tables(node, "projects", form: "[[projects]] tables") {
            config.projects = self.projects(projects)
        }
        return config
    }

    // MARK: [[projects]]

    /// Each `[[projects]]` table in file order. A table with a problem is
    /// left out, and its problem rejects the file.
    private func projects(_ nodes: [Node]) -> [ProjectEntry] {
        var projects: [ProjectEntry] = []
        var firstUse: [String: Int] = [:]
        for project in nodes {
            warnUnknownKeys(in: project, known: Self.projectKeys)
            let index = project.path.last.flatMap { if case .index(let index) = $0 { index } else { nil } } ?? projects.count
            guard project.table.contains(key: "slug") else {
                error("`\(project.path.dotted)` needs a `slug`", at: project.path)
                continue
            }
            guard let slug = string(project, "slug") else { continue }
            guard ProjectEntry.isSlug(slug) else {
                error(
                    "`\(project.path.dotted).slug` \(Self.tomlString(slug)) must be lowercase letters, digits and single hyphens",
                    at: project.path + [.key("slug")]
                )
                continue
            }
            if let first = firstUse[slug] {
                error(
                    "the project slug `\(slug)` is already used by `projects[\(first)]`; each project needs its own",
                    at: project.path + [.key("slug")]
                )
                continue
            }
            firstUse[slug] = index
            let title = string(project, "title")
            if title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
                error("`\(project.path.dotted).title` is empty; leave it out to use the slug", at: project.path + [.key("title")])
            }
            let versions = tables(project, "versions", form: "an array of { path, label } tables").map(self.versions) ?? []
            projects.append(ProjectEntry(slug: slug, title: title, versions: versions))
        }
        return projects
    }

    /// Each version of a project, in order. A version with a problem is
    /// left out, and its problem rejects the file.
    private func versions(_ nodes: [Node]) -> [ProjectEntry.Version] {
        var versions: [ProjectEntry.Version] = []
        for version in nodes {
            warnUnknownKeys(in: version, known: Self.versionKeys)
            guard version.table.contains(key: "path") else {
                error("`\(version.path.dotted)` needs a `path`", at: version.path)
                continue
            }
            guard let path = string(version, "path") else { continue }
            guard path.hasPrefix("/") || path == "~" || path.hasPrefix("~/") else {
                error(
                    "`\(version.path.dotted).path` must be an absolute path or start with `~/` (got \(Self.tomlString(path)))",
                    at: version.path + [.key("path")]
                )
                continue
            }
            let label = string(version, "label")
            versions.append(ProjectEntry.Version(path: path, label: label?.isEmpty == true ? nil : label))
        }
        return versions
    }

    // MARK: Typed reads
    //
    // Each returns nil when the key is absent, and records an error (and
    // returns nil) when it is there with the wrong type.

    func int(_ node: Node, _ key: String) -> Int? {
        guard node.table.contains(key: key) else { return nil }
        do {
            return try Int(clamping: node.table.integer(forKey: key))
        } catch {
            typeError(node, key, expected: "a whole number", error)
            return nil
        }
    }

    func string(_ node: Node, _ key: String) -> String? {
        guard node.table.contains(key: key) else { return nil }
        do {
            return try node.table.string(forKey: key)
        } catch {
            typeError(node, key, expected: "a string", error)
            return nil
        }
    }

    /// An array of tables, such as `[[projects]]` or an array of inline
    /// tables, each with its index in its path.
    func tables(_ node: Node, _ key: String, form: String) -> [Node]? {
        guard node.table.contains(key: key) else { return nil }
        do {
            let array = try node.table.array(forKey: key)
            var tables: [Node] = []
            for index in 0..<array.count {
                tables.append(Node(table: try array.table(atIndex: index), path: node.path + [.key(key), .index(index)]))
            }
            return tables
        } catch {
            typeError(node, key, expected: form, error)
            return nil
        }
    }

    // MARK: Recording

    /// Warns about each key of `node` that is not `known`, on its line,
    /// with the known key it most likely meant.
    private func warnUnknownKeys(in node: Node, known: [String]) {
        for key in node.table.keys.sorted() where !known.contains(key) {
            let path = node.path + [.key(key)]
            let hint = Suggestion.nearest(to: key, in: known).map { "; did you mean `\($0)`?" } ?? ""
            warnings.append(ConfigIssue(line: map.line(for: path), message: "unknown setting `\(path.dotted)` (ignored\(hint))"))
        }
    }

    private func typeError(_ node: Node, _ key: String, expected: String, _ underlying: any Error) {
        let path = node.path + [.key(key)]
        let (tomlLine, _) = ConfigIssue.splitLine(from: String(describing: underlying))
        errors.append(ConfigIssue(line: tomlLine ?? map.line(for: path), message: "`\(path.dotted)` must be \(expected)"))
    }

    private func error(_ message: String, at path: ConfigPath) {
        errors.append(ConfigIssue(line: map.line(for: path), message: message))
    }

    /// A TOML basic string with `"`, `\` and control characters escaped.
    static func tomlString(_ value: String) -> String {
        var out = "\""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\t": out += "\\t"
            case "\r": out += "\\r"
            default:
                if scalar.value < 0x20 || scalar.value == 0x7F {
                    out += String(format: "\\u%04X", scalar.value)
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        return out + "\""
    }
}

/// Picks the valid key a misspelt one most likely meant.
enum Suggestion {
    /// The closest candidate, if it is close enough to be a plausible typo:
    /// the same letters ignoring case and `-`/`_`, or within an edit
    /// distance of about a third of its length (at least 2).
    static func nearest(to input: String, in candidates: [String]) -> String? {
        let normalized = normalize(input)
        if let same = candidates.first(where: { normalize($0) == normalized }) { return same }
        let scored = candidates.map { ($0, distance(input.lowercased(), $0.lowercased())) }
        guard let best = scored.min(by: { $0.1 < $1.1 }) else { return nil }
        return best.1 <= max(2, best.0.count / 3) ? best.0 : nil
    }

    private static func normalize(_ text: String) -> String {
        text.lowercased().filter { $0 != "-" && $0 != "_" }
    }

    /// Levenshtein distance.
    static func distance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0...b.count)
        var current = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                current[j] = min(
                    previous[j] + 1,
                    current[j - 1] + 1,
                    previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1)
                )
            }
            swap(&previous, &current)
        }
        return previous[b.count]
    }
}
