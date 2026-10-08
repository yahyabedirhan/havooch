import Foundation

/// The version of a project a thread was raised on (ADR 0004, decision
/// E6): that version's file, by its absolute path. A thread keeps its
/// anchor whatever the project's list says later; its number comes from
/// the list as it is now (`ProjectOutline.tag`). A plain video's threads
/// have none. Kept as the path alone: `"anchor": "/Movies/cut1.mp4"`.
public struct VersionAnchor: Codable, Hashable, Sendable {
    /// The version's file, absolute and standardized.
    public var path: String

    public init(path: String) {
        self.path = path
    }

    public init(from decoder: any Decoder) throws {
        path = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(path)
    }
}

/// What a thread's anchor says against a project's list now: the version
/// number (from 1), or a removed version, whose path left the list. The
/// thread stays either way: nothing hides or closes it.
public enum VersionTag: Equatable, Sendable {
    case number(Int)
    case removed

    /// `v2`, or `Removed version`, as a thread's tag shows it.
    public var label: String {
        switch self {
        case .number(let number): "v\(number)"
        case .removed: "Removed version"
        }
    }

    /// The version's number; nil for a removed version.
    public var number: Int? {
        switch self {
        case .number(let number): number
        case .removed: nil
        }
    }
}

/// A project as the review's rules see it: its slug, its title and its
/// versions, in order, each an absolute path and a label. `config.toml`
/// holds the project (`ReviewConfig.ProjectEntry`); the app hands this
/// module its outline, so the rules here read no file.
public struct ProjectOutline: Equatable, Sendable {
    public struct Version: Equatable, Sendable {
        /// The version's file, absolute and standardized.
        public var path: String
        public var label: String?

        public init(path: String, label: String? = nil) {
            self.path = path
            self.label = label
        }
    }

    public var slug: String
    /// The name people read: the title, else the slug.
    public var title: String
    /// v1 first.
    public var versions: [Version]

    public init(slug: String, title: String, versions: [Version]) {
        self.slug = slug
        self.title = title
        self.versions = versions
    }

    /// The number (from 1) of the version at `path`; nil when no version
    /// is that file. A path listed twice is its first place.
    public func number(of path: String) -> Int? {
        versions.firstIndex { $0.path == path }.map { $0 + 1 }
    }

    /// The tag of a thread anchored at `anchor`: its version's number, or
    /// a removed version.
    public func tag(_ anchor: VersionAnchor) -> VersionTag {
        number(of: anchor.path).map(VersionTag.number) ?? .removed
    }

    /// The version numbered `number` (from 1); nil outside the list.
    public func version(_ number: Int) -> Version? {
        versions.indices.contains(number - 1) ? versions[number - 1] : nil
    }

    /// The anchor of the version numbered `number`; nil outside the list.
    public func anchor(_ number: Int) -> VersionAnchor? {
        version(number).map { VersionAnchor(path: $0.path) }
    }
}
