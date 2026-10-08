import Foundation
import ReviewCommand
import ReviewWire
import Testing

/// `project new`, `project add` and `project list` (ADR 0004, decision E3,
/// P4). `new` and `add` go through the app with no lease, the paths made
/// absolute; `add` brings the app's process to the front, as `open` does.
/// `list` reads `config.toml` itself and needs no app.
@Suite("The project commands")
struct ProjectCommandTests {
    static let pid: Int32 = 4242

    /// A run whose fake app answers every request, with two video files
    /// in its folder.
    private func makeRun() throws -> (run: Run, cut1: URL, cut2: URL) {
        let run = Run { message, _ in
            switch message.request {
            case .projectAdd: .success(ControlReply(ok: true, output: "added\n", pid: Self.pid))
            default: .success(.done("done\n"))
            }
        }
        try FileManager.default.createDirectory(at: run.folder, withIntermediateDirectories: true)
        let cut1 = run.folder.appendingPathComponent("cut1.mp4")
        let cut2 = run.folder.appendingPathComponent("cut2.mp4")
        try Data("one".utf8).write(to: cut1)
        try Data("two".utf8).write(to: cut2)
        return (run, cut1, cut2)
    }

    @Test("project new sends the slug, the absolute path and the title, with no lease, and brings nothing to the front")
    func new() throws {
        let (run, cut1, _) = try makeRun()
        defer { run.cleanUp() }
        #expect(run("project", "new", "launch-video", "--from", cut1.path, "--title", "Launch video").exitCode == 0)
        #expect(run.transport.requests == [.projectNew(slug: "launch-video", path: cut1.path, title: "Launch video")])
        #expect(ControlRequest.projectNew(slug: "a", path: "/a.mp4").role == .person)
        #expect(run.launcher.fronted.isEmpty)
    }

    @Test("project add sends the version with its label and brings the app's process to the front")
    func add() throws {
        let (run, _, cut2) = try makeRun()
        defer { run.cleanUp() }
        #expect(run("project", "add", "launch-video", cut2.path, "--label", "tighter intro") == CommandResult(output: "added\n"))
        #expect(run.transport.requests == [.projectAdd(slug: "launch-video", path: cut2.path, label: "tighter intro")])
        #expect(ControlRequest.projectAdd(slug: "a", path: "/a.mp4").role == .person)
        #expect(run.launcher.fronted == [Self.pid])
    }

    @Test("a path with no file is refused before the app is asked")
    func missingFile() throws {
        let (run, _, _) = try makeRun()
        defer { run.cleanUp() }
        let missing = run.folder.appendingPathComponent("cut9.mp4")
        #expect(run("project", "add", "launch-video", missing.path) == .refused("havooch project add: no video file at \(missing.path)"))
        #expect(run("project", "new", "launch-video", "--from", missing.path).exitCode == 1)
        #expect(run.transport.requests.isEmpty)
    }

    @Test("open --project sends the project with the path")
    func openInProject() throws {
        let (run, cut1, _) = try makeRun()
        defer { run.cleanUp() }
        _ = run("open", cut1.path, "--project", "launch-video")
        #expect(run.transport.requests == [.open(path: cut1.path, project: "launch-video")])
    }

    @Test("project list reads config.toml with no app: each project with its versions, ~ made absolute, and --json")
    func list() throws {
        let run = Run()
        defer { run.cleanUp() }
        #expect(run("project", "list") == CommandResult(output: "no projects; make one with `havooch project new <slug> --from <video>`\n"))
        let file = run.support.appendingPathComponent("config/config.toml")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("""
            version = 1

            [[projects]]
            slug = "launch-video"
            title = "Launch video"
            versions = [
              { path = "/Movies/cut1.mp4" },
              { path = "/Movies/cut2.mp4", label = "tighter intro" },
            ]

            [[projects]]
            slug = "teaser"
            versions = []

            """.utf8).write(to: file)
        #expect(run("project", "list") == CommandResult(output: """
            launch-video "Launch video", 2 versions
              v1 /Movies/cut1.mp4
              v2 /Movies/cut2.mp4 (tighter intro)
            teaser "teaser", 0 versions

            """))
        let json = try #require(JSONSerialization.jsonObject(with: Data(run("project", "list", "--json").output.utf8)) as? [String: Any])
        let projects = try #require(json["projects"] as? [[String: Any]])
        #expect(projects.map { $0["slug"] as? String } == ["launch-video", "teaser"])
        let versions = try #require(projects[0]["versions"] as? [[String: Any]])
        #expect(versions.map { $0["number"] as? Int } == [1, 2])
        #expect(versions[0]["label"] is NSNull)
        #expect(versions[1]["label"] as? String == "tighter intro")
        #expect(run.transport.requests.isEmpty)

        try Data("version = 1\n[[projects]]\ntitle = \"No slug\"\n".utf8).write(to: file)
        #expect(run("project", "list").exitCode == 1)
    }
}
