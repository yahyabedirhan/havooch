import Foundation
import ReviewConfig
import Testing

/// `config.toml` as Havooch reads it: every key, the problems that reject a
/// file, each on its line, and the warnings that don't.
@Suite("Reading config.toml")
struct ConfigFileTests {
    /// A file that sets every key Havooch reads.
    static let everyKey = """
        #:schema \(ConfigFile.schemaURL)
        version = 1
        theme = "Dimmed" # pinned

        [[projects]]
        slug = "launch-video"
        title = "Launch video"
        versions = [
          { path = "~/Movies/cut1.mp4" },
          { path = "/Users/me/Movies/cut2.mp4", label = "tighter intro" },
        ]

        [[projects]]
        slug = "intro"

        """

    private func problems(_ text: String) -> [ConfigIssue] {
        do throws(ConfigProblems) {
            _ = try ConfigFile.decode(text)
            return []
        } catch {
            return error.problems
        }
    }

    @Test("a file with every key reads as its theme and its projects, in order, with no warning")
    func everyKey() throws {
        let decoded = try ConfigFile.decode(Self.everyKey)
        #expect(decoded.warnings == [])
        #expect(decoded.config == ConfigFile(theme: "Dimmed", projects: [
            ProjectEntry(slug: "launch-video", title: "Launch video", versions: [
                .init(path: "~/Movies/cut1.mp4"), .init(path: "/Users/me/Movies/cut2.mp4", label: "tighter intro"),
            ]),
            ProjectEntry(slug: "intro"),
        ]))
        #expect(decoded.config.projects[1].displayTitle == "intro")
    }

    @Test("an empty file, one of comments only and the header are every default")
    func defaults() throws {
        #expect(try ConfigFile.decode("").config == ConfigFile())
        #expect(try ConfigFile.decode("# nothing yet\n").config == ConfigFile())
        let header = try ConfigFile.decode(ConfigFile.header)
        #expect(header.config == ConfigFile())
        #expect(header.warnings == [])
        #expect(ConfigFile.header.hasPrefix("#:schema \(ConfigFile.schemaURL)\n"))
    }

    @Test("invalid TOML is a problem on its line")
    func invalidTOML() {
        let found = problems("version = 1\ntheme = \"Dimmed\nfoo = 2\n")
        #expect(found.count == 1)
        #expect(found.first?.line == 2)
        #expect(found.first?.message.hasPrefix("invalid TOML") == true)
    }

    @Test("a file that sets a key needs version 1; another version is a problem on its line")
    func version() {
        #expect(problems("theme = \"Dimmed\"\n") == [ConfigIssue(line: 1, message: "the file needs `version = 1` at its top")])
        #expect(problems("# c\nversion = 2\n") == [
            ConfigIssue(line: 2, message: "`version` 2 is not supported; this Havooch reads version 1"),
        ])
        #expect(problems("version = \"1\"\n").first?.message == "`version` must be a whole number")
    }

    @Test("a theme of the wrong type or empty is a problem on its line")
    func theme() {
        #expect(problems("version = 1\ntheme = 3\n") == [ConfigIssue(line: 2, message: "`theme` must be a string")])
        #expect(problems("version = 1\n\ntheme = \" \"\n").first?.line == 3)
    }

    @Test("an unknown key is a warning on its line, with the key it most likely meant, and the file still reads")
    func unknownKey() throws {
        let decoded = try ConfigFile.decode("version = 1\nthem = \"Dimmed\"\n[[projects]]\nslug = \"a\"\ntitel = \"A\"\n")
        #expect(decoded.config == ConfigFile(projects: [ProjectEntry(slug: "a")]))
        #expect(decoded.warnings == [
            ConfigIssue(line: 2, message: "unknown setting `them` (ignored; did you mean `theme`?)"),
            ConfigIssue(line: 5, message: "unknown setting `projects[0].titel` (ignored; did you mean `title`?)"),
        ])
    }

    @Test("projects: a missing or bad slug, a slug used twice, an empty title, a relative or missing path are problems on their lines")
    func projectProblems() {
        let text = """
            version = 1
            [[projects]]
            title = "No slug"
            [[projects]]
            slug = "Launch Video"
            [[projects]]
            slug = "a"
            title = ""
            versions = [{ path = "cut1.mp4" }, { label = "no path" }]
            [[projects]]
            slug = "a"

            """
        #expect(problems(text) == [
            ConfigIssue(line: 2, message: "`projects[0]` needs a `slug`"),
            ConfigIssue(line: 5, message: "`projects[1].slug` \"Launch Video\" must be lowercase letters, digits and single hyphens"),
            ConfigIssue(line: 8, message: "`projects[2].title` is empty; leave it out to use the slug"),
            ConfigIssue(line: 9, message: "`projects[2].versions[0].path` must be an absolute path or start with `~/` (got \"cut1.mp4\")"),
            ConfigIssue(line: 9, message: "`projects[2].versions[1]` needs a `path`"),
            ConfigIssue(line: 11, message: "the project slug `a` is already used by `projects[2]`; each project needs its own"),
        ])
        #expect(problems("version = 1\nprojects = 3\n") == [ConfigIssue(line: 2, message: "`projects` must be [[projects]] tables")])
    }

    @Test("a slug is lowercase letters, digits and single hyphens, up to 64")
    func slugs() {
        #expect(ProjectEntry.isSlug("launch-video-2"))
        #expect(!ProjectEntry.isSlug(""))
        #expect(!ProjectEntry.isSlug("-a"))
        #expect(!ProjectEntry.isSlug("a--b"))
        #expect(!ProjectEntry.isSlug("Launch"))
        #expect(!ProjectEntry.isSlug(String(repeating: "a", count: 65)))
    }

    @Test("a version's number is its place in the list, from 1, with ~ for the home folder")
    func versionNumber() {
        let location = ConfigLocation(folder: URL(fileURLWithPath: "/c"), home: URL(fileURLWithPath: "/Users/me"))
        let project = ProjectEntry(slug: "a", versions: [.init(path: "~/Movies/cut1.mp4"), .init(path: "/Users/me/Movies/cut2.mp4")])
        #expect(project.versionNumber(of: URL(fileURLWithPath: "/Users/me/Movies/cut1.mp4"), in: location) == 1)
        #expect(project.versionNumber(of: URL(fileURLWithPath: "/Users/me/Movies/../Movies/cut2.mp4"), in: location) == 2)
        #expect(project.versionNumber(of: URL(fileURLWithPath: "/Users/me/Movies/cut3.mp4"), in: location) == nil)
    }
}

/// Where the file is: a moved support folder first, then
/// `XDG_CONFIG_HOME`, then `~/.config`.
@Suite("Where config.toml is")
struct ConfigLocationTests {
    @Test("~/.config/havooch by default, with config.toml and themes/ in it")
    func standard() {
        let location = ConfigLocation(variables: ["HOME": "/Users/me"], movedSupport: nil)
        #expect(location.folder.path == "/Users/me/.config/havooch")
        #expect(location.file.path == "/Users/me/.config/havooch/config.toml")
        #expect(location.themesFolder.path == "/Users/me/.config/havooch/themes")
        #expect(location.expand("~/Movies/a.mp4").path == "/Users/me/Movies/a.mp4")
    }

    @Test("XDG_CONFIG_HOME moves it when it is an absolute path")
    func xdg() {
        #expect(ConfigLocation(variables: ["HOME": "/Users/me", "XDG_CONFIG_HOME": "/x"], movedSupport: nil).file.path == "/x/havooch/config.toml")
        #expect(ConfigLocation(variables: ["HOME": "/Users/me", "XDG_CONFIG_HOME": "x"], movedSupport: nil).folder.path == "/Users/me/.config/havooch")
    }

    @Test("a support folder HAVOOCH_SUPPORT_DIR moves takes the settings with it, before XDG_CONFIG_HOME")
    func movedSupport() {
        let location = ConfigLocation(
            variables: ["HOME": "/Users/me", "XDG_CONFIG_HOME": "/x"], movedSupport: URL(fileURLWithPath: "/tmp/hv-84", isDirectory: true)
        )
        #expect(location.file.path == "/tmp/hv-84/config/config.toml")
        #expect(location.themesFolder.path == "/tmp/hv-84/config/themes")
    }
}
