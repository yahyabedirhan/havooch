import Foundation
@testable import ReviewConfig
import Testing

/// The two project writes of `config.toml`: append a
/// `[[projects]]` table, and append a version to one project. Each keeps
/// every other line and comment, and is refused unless the file reads back
/// with only its change.
@Suite("Project writes of config.toml")
struct ProjectWriterTests {
    static let file = """
        #:schema https://example.com/config.schema.json
        version = 1
        theme = "Dimmed" # my pick

        # The launch film.
        [[projects]]
        slug = "launch-video"
        title = "Launch video"
        versions = [
          { path = "/Movies/cut1.mp4" }, # the first cut
        ]

        """

    @Test("a new project goes at the end as a [[projects]] table with v1, every comment kept")
    func appendProject() throws {
        let edited = try ConfigWriter.appendingProject(
            slug: "teaser", title: "Teaser", firstVersion: .init(path: "/Movies/teaser.mp4"), to: Self.file
        )
        #expect(edited == Self.file + """

            [[projects]]
            slug = "teaser"
            title = "Teaser"
            versions = [
              { path = "/Movies/teaser.mp4" },
            ]

            """)
        let config = try ConfigFile.decode(edited).config
        #expect(config.projects.map(\.slug) == ["launch-video", "teaser"])
        #expect(config.theme == "Dimmed")
    }

    @Test("a project with no title, in a file that has none, is the slug and its first version")
    func appendToHeader() throws {
        let edited = try ConfigWriter.appendingProject(slug: "a", title: nil, firstVersion: .init(path: "~/Movies/a.mp4"), to: "version = 1\n")
        #expect(edited == "version = 1\n\n[[projects]]\nslug = \"a\"\nversions = [\n  { path = \"~/Movies/a.mp4\" },\n]\n")
    }

    @Test("a slug in use, a slug that isn't one, an empty title, a relative path and a file that doesn't read are refused")
    func projectRefusals() {
        #expect(throws: ConfigWriteFailure("a project called `launch-video` is in config.toml already")) {
            try ConfigWriter.appendingProject(slug: "launch-video", title: nil, firstVersion: .init(path: "/a.mp4"), to: Self.file)
        }
        #expect(throws: ConfigWriteFailure.self) {
            try ConfigWriter.appendingProject(slug: "Launch Video", title: nil, firstVersion: .init(path: "/a.mp4"), to: Self.file)
        }
        #expect(throws: ConfigWriteFailure.self) {
            try ConfigWriter.appendingProject(slug: "b", title: " ", firstVersion: .init(path: "/a.mp4"), to: Self.file)
        }
        #expect(throws: ConfigWriteFailure("a version's path must be absolute, not `cuts/a.mp4`")) {
            try ConfigWriter.appendingProject(slug: "b", title: nil, firstVersion: .init(path: "cuts/a.mp4"), to: Self.file)
        }
        #expect(throws: ConfigWriteFailure.self) {
            try ConfigWriter.appendingProject(slug: "b", title: nil, firstVersion: .init(path: "/a.mp4"), to: "version = \n")
        }
    }

    @Test("a version goes after the project's last: only its versions array is written again")
    func appendVersion() throws {
        let edited = try ConfigWriter.appendingVersion(
            .init(path: "/Movies/cut2.mp4", label: "tighter intro"), toProject: "launch-video", in: Self.file
        )
        #expect(edited == """
            #:schema https://example.com/config.schema.json
            version = 1
            theme = "Dimmed" # my pick

            # The launch film.
            [[projects]]
            slug = "launch-video"
            title = "Launch video"
            versions = [
              { path = "/Movies/cut1.mp4" },
              { path = "/Movies/cut2.mp4", label = "tighter intro" },
            ]

            """)
    }

    @Test("a version goes to the project the slug names, whether its versions are on one line, missing or tables")
    func versionForms() throws {
        let file = """
            version = 1

            [[projects]]
            slug = "a"
            versions = [{ path = "/a1.mp4" }]

            [[projects]]
            slug = "b"
            title = "B"

            [[projects]]
            slug = "c"

            [[projects.versions]]
            path = "/c1.mp4"

            [[projects]]
            slug = "d"
            versions = []

            """
        let a = try ConfigFile.decode(ConfigWriter.appendingVersion(.init(path: "/a2.mp4"), toProject: "a", in: file)).config
        #expect(a.project("a")?.versions.map(\.path) == ["/a1.mp4", "/a2.mp4"])
        let b = try ConfigFile.decode(ConfigWriter.appendingVersion(.init(path: "/b1.mp4"), toProject: "b", in: file)).config
        #expect(b.project("b")?.versions.map(\.path) == ["/b1.mp4"])
        #expect(b.project("b")?.title == "B")
        let c = try ConfigFile.decode(ConfigWriter.appendingVersion(.init(path: "/c2.mp4", label: "two"), toProject: "c", in: file)).config
        #expect(c.project("c")?.versions == [.init(path: "/c1.mp4"), .init(path: "/c2.mp4", label: "two")])
        #expect(c.project("d")?.versions == [])
        let d = try ConfigFile.decode(ConfigWriter.appendingVersion(.init(path: "/d1.mp4"), toProject: "d", in: file)).config
        #expect(d.project("d")?.versions.map(\.path) == ["/d1.mp4"])
        #expect(d.projects.map(\.slug) == ["a", "b", "c", "d"])
    }

    @Test("a version for a slug no project has names the projects there are")
    func unknownProject() {
        #expect(throws: ConfigWriteFailure("no project `launch-videoo`; the projects are launch-video")) {
            try ConfigWriter.appendingVersion(.init(path: "/a.mp4"), toProject: "launch-videoo", in: Self.file)
        }
    }

    @Test("the location writes the file in place, making it from the header when it is missing")
    func location() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("havooch-config-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let location = ConfigLocation(folder: folder, home: URL(fileURLWithPath: "/Users/me"))
        try location.addProject(slug: "launch-video", title: nil, firstVersion: .init(path: "/Movies/cut1.mp4"))
        try location.addVersion(.init(path: "/Movies/cut2.mp4"), toProject: "launch-video")
        let config = try location.read().config
        #expect(config.project("launch-video")?.versions.map(\.path) == ["/Movies/cut1.mp4", "/Movies/cut2.mp4"])
        let text = try String(contentsOf: location.file, encoding: .utf8)
        #expect(text.hasPrefix(ConfigFile.header))
        let listing = config.projects(listing: URL(fileURLWithPath: "/Movies/cut2.mp4"), in: location)
        #expect(listing.map(\.slug) == ["launch-video"])
    }
}
