import Foundation

/// One `[[projects]]` table of `config.toml`: the versions of one
/// video, in order. Version number = position + 1. The videos stay where
/// they are; a version is a path and an optional label.
public struct ProjectEntry: Equatable, Sendable {
    /// One version: the video's path as the file writes it (absolute, or
    /// from `~/`), and its label.
    public struct Version: Equatable, Sendable {
        public var path: String
        public var label: String?

        public init(path: String, label: String? = nil) {
            self.path = path
            self.label = label
        }
    }

    /// The project's name in commands and in `--project`: lowercase
    /// letters, digits and single hyphens.
    public var slug: String
    /// The name people read; nil shows the slug.
    public var title: String?
    public var versions: [Version]

    public init(slug: String, title: String? = nil, versions: [Version] = []) {
        self.slug = slug
        self.title = title
        self.versions = versions
    }

    /// The title, else the slug.
    public var displayTitle: String { title ?? slug }

    /// The number of the version at `url` (from 1), with `~` standing for
    /// `location`'s home folder; nil when no version is that file.
    public func versionNumber(of url: URL, in location: ConfigLocation) -> Int? {
        let wanted = url.standardizedFileURL.path
        return versions.firstIndex { location.expand($0.path).standardizedFileURL.path == wanted }.map { $0 + 1 }
    }

    /// Whether `slug` is a slug: 1 to 64 of lowercase letters, digits and
    /// single hyphens, with a letter or a digit at each end.
    public static func isSlug(_ slug: String) -> Bool {
        guard (1...64).contains(slug.count), slug.first != "-", slug.last != "-", !slug.contains("--") else { return false }
        return slug.allSatisfy { ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "-" }
    }
}
