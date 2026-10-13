import Foundation

// The two project writes of `config.toml`: append a
// `[[projects]]` table, and append a version to one project's `versions`.
// Like the theme line, each changes only its own lines, and is refused
// unless the result reads back as the file's settings with only that change.

extension ConfigWriter {
    /// `text` with a new `[[projects]]` table at its end: `slug`, `title`
    /// when there is one, and `versions` holding `firstVersion`, which is
    /// v1. Every other line and comment stays.
    ///
    /// Refused: a file that doesn't read, a slug that isn't one or that a
    /// project already uses, an empty title, a path that isn't absolute,
    /// and a result that wouldn't read back with only the project added.
    public static func appendingProject(
        slug: String, title: String?, firstVersion: ProjectEntry.Version, to text: String
    ) throws(ConfigWriteFailure) -> String {
        let before = try decoded(text)
        guard ProjectEntry.isSlug(slug) else {
            throw ConfigWriteFailure("`\(slug)` isn't a slug: use lowercase letters, digits and single hyphens")
        }
        guard !before.config.projects.contains(where: { $0.slug == slug }) else {
            throw ConfigWriteFailure("a project called `\(slug)` is in config.toml already")
        }
        if let title, title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ConfigWriteFailure("a title needs words; leave it out to use the slug")
        }
        try needAbsolute(firstVersion.path)
        var table = ["[[projects]]", "slug = \(ConfigReader.tomlString(slug))"]
        if let title { table.append("title = \(ConfigReader.tomlString(title))") }
        table += versionsArray([firstVersion], lead: "")
        var lines = text.components(separatedBy: "\n")
        // The file ends on one empty line; the table goes after a blank one.
        while lines.last == "" { lines.removeLast() }
        if !lines.isEmpty { lines.append("") }
        lines += table + [""]
        let edited = lines.joined(separator: "\n")

        var expected = before.config
        expected.projects.append(ProjectEntry(slug: slug, title: title, versions: [firstVersion]))
        try readsBack(edited, as: expected, warnings: before.warnings, change: "the project added")
        return edited
    }

    /// `text` with `version` after the last version of the project `slug`.
    /// Only that project's `versions` array is written again; a project
    /// written with `[[projects.versions]]` tables gets one more table, and
    /// one with no `versions` gets the key. Every other line stays.
    ///
    /// Refused: a file that doesn't read, a slug no project has, a path
    /// that isn't absolute, and a result that wouldn't read back with only
    /// the version added.
    public static func appendingVersion(
        _ version: ProjectEntry.Version, toProject slug: String, in text: String
    ) throws(ConfigWriteFailure) -> String {
        let before = try decoded(text)
        guard let index = before.config.projects.firstIndex(where: { $0.slug == slug }) else {
            let known = before.config.projects.map(\.slug)
            throw ConfigWriteFailure(
                "no project `\(slug)`; " + (known.isEmpty ? "there are no projects" : "the projects are \(known.joined(separator: ", "))")
            )
        }
        try needAbsolute(version.path)
        let project = before.config.projects[index]
        let map = TOMLSourceMap(text)
        // A file that reads has every project, in the file's order.
        let table: ConfigPath = [.key("projects"), .index(index)]
        guard map.entries.contains(where: { $0.isHeader && $0.path == table }) else {
            throw ConfigWriteFailure("the project `\(slug)` isn't written as a [[projects]] table")
        }
        var lines = text.components(separatedBy: "\n")
        let inTable = map.entries.filter { $0.path.starts(with: table) }
        if let entry = inTable.first(where: { !$0.isHeader && $0.path == table + [.key("versions")] }) {
            let first = lines[entry.line - 1]
            let lead = String(first.prefix { $0 == " " || $0 == "\t" })
            lines.replaceSubrange((entry.line - 1)..<entry.endLine, with: versionsArray(project.versions + [version], lead: lead))
        } else if inTable.contains(where: { $0.isHeader && $0.path.count > 2 && $0.path[2] == .key("versions") }) {
            let end = inTable.map(\.endLine).max() ?? lines.count
            var body = ["[[projects.versions]]", "path = \(ConfigReader.tomlString(version.path))"]
            if let label = version.label { body.append("label = \(ConfigReader.tomlString(label))") }
            // After the project's last version, past its trailing blank lines.
            var at = end
            while at > 0, lines[at - 1].trimmingCharacters(in: .whitespaces).isEmpty { at -= 1 }
            lines.insert(contentsOf: [""] + body, at: at)
        } else {
            let keys = inTable.filter { !$0.isHeader && $0.path.count == 3 }
            guard let last = keys.map(\.endLine).max() else {
                throw ConfigWriteFailure("the project `\(slug)` isn't written as a [[projects]] table")
            }
            lines.insert(contentsOf: versionsArray([version], lead: ""), at: last)
        }
        let edited = lines.joined(separator: "\n")

        var expected = before.config
        expected.projects[index].versions.append(version)
        try readsBack(edited, as: expected, warnings: before.warnings, change: "the version added")
        return edited
    }

    // MARK: - Helpers

    /// `versions = [` with one `{ path, label }` per line, then `]`.
    static func versionsArray(_ versions: [ProjectEntry.Version], lead: String) -> [String] {
        let items = versions.map { version in
            let label = version.label.map { ", label = \(ConfigReader.tomlString($0))" } ?? ""
            return "\(lead)  { path = \(ConfigReader.tomlString(version.path))\(label) },"
        }
        return ["\(lead)versions = ["] + items + ["\(lead)]"]
    }

    private static func decoded(_ text: String) throws(ConfigWriteFailure) -> ConfigFile.Decoded {
        do throws(ConfigProblems) {
            return try ConfigFile.decode(text)
        } catch {
            throw ConfigWriteFailure("config.toml has a problem: \(error.line)")
        }
    }

    private static func needAbsolute(_ path: String) throws(ConfigWriteFailure) {
        guard path.hasPrefix("/") || path.hasPrefix("~/") else {
            throw ConfigWriteFailure("a version's path must be absolute, not `\(path)`")
        }
    }

    /// Refused unless `edited` reads as `expected`, with the same warnings.
    private static func readsBack(
        _ edited: String, as expected: ConfigFile, warnings: [ConfigIssue], change: String
    ) throws(ConfigWriteFailure) {
        guard let after = try? ConfigFile.decode(edited), after.config == expected, after.warnings.map(\.message) == warnings.map(\.message)
        else {
            throw ConfigWriteFailure("the edit wouldn't read back as the same settings with only \(change)")
        }
    }
}

extension ConfigLocation {
    /// Appends the project `slug` with `firstVersion` as v1
    /// (`ConfigWriter.appendingProject`), creating the file from the
    /// header when it is missing.
    public func addProject(slug: String, title: String?, firstVersion: ProjectEntry.Version) throws(ConfigWriteFailure) {
        try createIfMissing()
        try edit { text throws(ConfigWriteFailure) in
            try ConfigWriter.appendingProject(slug: slug, title: title, firstVersion: firstVersion, to: text)
        }
    }

    /// Appends `version` to the project `slug` (`ConfigWriter.appendingVersion`).
    public func addVersion(_ version: ProjectEntry.Version, toProject slug: String) throws(ConfigWriteFailure) {
        try createIfMissing()
        try edit { text throws(ConfigWriteFailure) in try ConfigWriter.appendingVersion(version, toProject: slug, in: text) }
    }
}

extension ConfigFile {
    /// The project `slug`; nil when there's none.
    public func project(_ slug: String) -> ProjectEntry? {
        projects.first { $0.slug == slug }
    }

    /// The projects that list the file at `url` as a version, in the
    /// file's order, with `~` standing for `location`'s home folder.
    public func projects(listing url: URL, in location: ConfigLocation) -> [ProjectEntry] {
        projects.filter { $0.versionNumber(of: url, in: location) != nil }
    }
}
