import Foundation
@testable import ReviewApp
import ReviewConfig
import ReviewCore
import ReviewLease
import ReviewSetup
import ReviewStore
import ReviewWire
import Testing

/// Projects (ADR 0004, decisions C4 and E1 to E8, P3 and P4), through the
/// app model and its control server with no scene and no socket: `project
/// new` moves a plain video's review into a project and keeps its listener;
/// `project add` shows the next version; threads are anchored to their
/// version and tagged; `open` picks the most recently used project; `wait
/// --project` binds to a project; the payload carries the project.
@Suite("Projects", .serialized)
struct ProjectTests {
    static let claude = Holder(key: "claude-1", name: "Claude Code", place: "/Users/me/shop")
    static let cut1 = MessageTests.fixture.standardizedFileURL
    static let cut2 = WindowTests.launch.standardizedFileURL

    let support = FileManager.default.temporaryDirectory
        .appendingPathComponent("havooch-tests-\(UUID().uuidString)", isDirectory: true)

    private func cleanUp() {
        try? FileManager.default.removeItem(at: support)
    }

    /// The app on a fresh folder with the sample open in `w1`, one message
    /// queued on it at 0:02, and the server in front of it.
    private func run() async throws -> (app: AppModel, window: WindowModel, server: ControlServer) {
        let app = AppModel(environment: [SupportFolder.overrideVariable: support.path], speech: SlowRecognizer())
        let window = app.makeWindow()
        try await window.open(Self.cut1)
        _ = try await window.addMessage(text: "Too fast here", at: 2)
        let server = ControlServer(
            socket: URL(fileURLWithPath: "/nowhere/control.sock"), app: app, listeners: { app.listeners },
            screenshotter: ControlServerTests.FakeScreenshotter(), quit: {}
        )
        return (app, window, server)
    }

    private func ask(_ request: ControlRequest, _ server: ControlServer, json: Bool = false) async -> ControlReply {
        await server.replyWritten(to: request.sent(by: Self.claude, json: json)).reply
    }

    private func object(_ output: String) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any])
    }

    private func eventually(_ condition: () -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(10)
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test("project new makes the video v1: its threads move in with their ids, anchored to v1, and its listener keeps listening")
    func projectNew() async throws {
        defer { cleanUp() }
        let (app, window, server) = try await run()
        let before = try #require(window.review)
        let hash = try #require(window.video?.contentHash)
        let wait = Task { await server.replyWritten(to: ControlRequest.wait(timeoutSeconds: 30, video: Self.cut1.path).sent(by: Self.claude)) }
        await eventually { window.listeners().outbox.isWaitOpen }

        let made = await ask(.projectNew(slug: "launch-video", path: Self.cut1.path, title: "Launch video"), server)
        #expect(made.ok)
        #expect(made.output == "project launch-video made with sample.mp4 as v1\n")
        #expect(app.config.config.project("launch-video")?.versions.map(\.path) == [Self.cut1.path])
        #expect(window.project == "launch-video")
        #expect(window.reviewKey == .project(slug: "launch-video"))
        #expect(window.target == .project(slug: "launch-video"))
        let after = try #require(window.review)
        #expect(after.hash8 == before.hash8)
        #expect(after.threads.map(\.id) == before.threads.map(\.id))
        #expect(after.threads.map(\.anchor) == [nil, VersionAnchor(path: Self.cut1.path)])
        // The files moved, and the plain video's review is gone.
        let layout = SupportLayout(root: support)
        #expect(FileManager.default.fileExists(atPath: layout.reviewFile(.project(slug: "launch-video")).path))
        #expect(!FileManager.default.fileExists(atPath: layout.reviewFile(.video(contentHash: hash)).path))
        #expect(FileManager.default.fileExists(atPath: layout.keyframe(after.threads[1].id, of: .project(slug: "launch-video")).path))

        // The listener's wait stayed open, and takes the project's send.
        #expect(window.listeners().key == .project(slug: "launch-video"))
        #expect(window.listeners().outbox.isWaitOpen)
        let send = try await window.sendQueue()
        let answer = await wait.value
        #expect(answer.delivered?.sendID.text == send.id)
        let payload = try object(answer.reply.output)
        let project = try #require(payload["project"] as? [String: Any])
        #expect(project["slug"] as? String == "launch-video")
        #expect(project["title"] as? String == "Launch video")
        #expect(project["onScreen"] as? Int == 1)
        let threads = try #require(payload["threads"] as? [[String: Any]])
        #expect((threads[0]["version"] as? [String: Any])?["number"] as? Int == 1)
        #expect(FileManager.default.fileExists(atPath: layout.outboxFile(.project(slug: "launch-video")).path))
        #expect(!FileManager.default.fileExists(atPath: layout.outboxFile(.video(contentHash: hash)).path))

        // state --json names the project and each thread's version.
        let state = try object(await ask(.state, server, json: true).output)
        let reported = try #require(state["project"] as? [String: Any])
        #expect(reported["slug"] as? String == "launch-video")
        #expect(reported["version"] as? Int == 1)
        let held = try #require((state["windows"] as? [[String: Any]])?.first?["video"] as? [String: Any])
        #expect(held["project"] as? String == "launch-video")
        #expect(held["version"] as? Int == 1)
        #expect(((state["threads"] as? [[String: Any]])?[1]["version"] as? [String: Any])?["number"] as? Int == 1)
        #expect(window.projectWords?.title == "Launch video")
        #expect(window.projectWords?.version.hasPrefix("v1") == true)
        // The copied prompt names the project, so the agent listens to it.
        #expect(window.promptTarget == .project(slug: "launch-video"))

        // A slug in use is refused.
        let again = await ask(.projectNew(slug: "launch-video", path: Self.cut2.path), server)
        #expect(again.error.contains("a project called `launch-video` is in config.toml already"))
        app.listeners.stop()
    }

    @Test("project add appends the next version and shows it; new threads anchor to it, v1's stay open beside them, tagged")
    func projectAdd() async throws {
        defer { cleanUp() }
        let (app, window, server) = try await run()
        #expect(await ask(.projectNew(slug: "launch-video", path: Self.cut1.path), server).ok)

        let added = await ask(.projectAdd(slug: "launch-video", path: Self.cut2.path, label: "tighter intro"), server)
        #expect(added.ok)
        #expect(added.output == "havooch-demo.mp4 added to launch-video as v2, shown in w1\n")
        #expect(added.pid != nil)
        #expect(app.config.config.project("launch-video")?.versions
            == [.init(path: Self.cut1.path), .init(path: Self.cut2.path, label: "tighter intro")])
        #expect(window.video?.url == Self.cut2)
        #expect(window.versionNumber == 2)

        // A thread at the same time on v2 is a new one; the pins show v2's only.
        let written = try await window.addMessage(text: "Logo too small", at: 2)
        #expect(written.thread.number == 2)
        #expect(written.thread.version?.number == 2)
        #expect(window.frameThreads.map(\.number) == [2])
        #expect(window.threads.map(\.number) == [0, 1, 2])
        #expect(window.threads.compactMap(window.versionTag(of:)) == [.number(1), .number(2)])

        // The same video again, and an unknown project, are refused.
        #expect(await ask(.projectAdd(slug: "launch-video", path: Self.cut2.path), server).error
            == "havooch-demo.mp4 is v2 of launch-video already")
        #expect(await ask(.projectAdd(slug: "launch-videoo", path: Self.cut2.path), server).error
            == "no project `launch-videoo` in config.toml; the projects are launch-video")

        // A thread of v1 opens v1; nothing hides it.
        _ = try await window.showThread("1")
        #expect(window.video?.url == Self.cut1)
        #expect(window.versionNumber == 1)

        // v1 leaves the list by hand: its thread stays, tagged as a removed version.
        try Data("""
            version = 1

            [[projects]]
            slug = "launch-video"
            versions = [{ path = "\(Self.cut2.path)" }]

            """.utf8).write(to: app.config.location.file)
        app.config.reload()
        #expect(window.threads.map(\.number) == [0, 1, 2])
        #expect(window.threads.compactMap(window.versionTag(of:)) == [.removed, .number(1)])
        #expect(window.state().threads[1].version == StateReport.Version(number: nil, path: Self.cut1.path, label: nil))
        #expect(window.projectWords == HeaderWords.Project(title: "launch-video", version: "a removed version"))
        // Words still go on it, on the whole frame.
        #expect(try await window.addMessage(text: "Still too fast", at: nil, thread: "1").thread.number == 1)
        app.listeners.stop()
    }

    @Test("open picks the most recently used project that lists the video, --project chooses, and a second project starts fresh")
    func openResolves() async throws {
        defer { cleanUp() }
        let (app, window, server) = try await run()
        #expect(await ask(.projectNew(slug: "launch-video", path: Self.cut1.path), server).ok)
        #expect(await ask(.projectNew(slug: "teaser", path: Self.cut1.path), server).ok)
        // The second project didn't take the threads: the window keeps the first.
        #expect(window.project == "launch-video")
        #expect(window.threads.count == 2)

        // The first was used last: the video opens there, in its window.
        let hash = try #require(window.video?.contentHash)
        #expect(try app.resolveTarget(Self.cut1, contentHash: hash, project: nil) == .project(slug: "launch-video"))
        let opened = await ask(.open(path: Self.cut1.path), server)
        #expect(opened.ok)
        #expect(opened.output.contains("in project launch-video (v1) in w1"))

        // --project chooses the other, which has no threads of its own yet.
        let teaser = await ask(.open(path: Self.cut1.path, project: "teaser"), server)
        #expect(teaser.ok)
        let other = try #require(app.windows.holding(.project(slug: "teaser")))
        #expect(other !== window)
        #expect(other.threads.map(\.number) == [0])
        #expect(other.review?.hash8 != window.review?.hash8)
        // Now the teaser is the one used last.
        #expect(try app.resolveTarget(Self.cut1, contentHash: hash, project: nil) == .project(slug: "teaser"))
        #expect(app.homeProjects.map(\.slug) == ["teaser", "launch-video"])

        // A project that doesn't list the file, and one there isn't, are refused.
        #expect(await ask(.open(path: Self.cut2.path, project: "teaser"), server).error.contains("the project teaser doesn't list"))
        #expect(await ask(.open(path: Self.cut1.path, project: "nope"), server).error.hasPrefix("no project `nope` in config.toml"))
        app.listeners.stop()
    }

    @Test("wait --project binds to the project's review, and an unknown project is refused")
    func waitForProject() async throws {
        defer { cleanUp() }
        let (app, window, server) = try await run()
        #expect(await ask(.projectNew(slug: "launch-video", path: Self.cut1.path), server).ok)
        let unknown = await ask(.wait(timeoutSeconds: 0, project: "nope"), server)
        #expect(unknown.error == "no project `nope` in config.toml; the projects are launch-video")

        let send = try await window.sendQueue()
        let taken = await server.replyWritten(to: ControlRequest.wait(timeoutSeconds: 0, project: "launch-video").sent(by: Self.claude))
        #expect(taken.delivered?.sendID.text == send.id)
        #expect(taken.delivered?.review == .project(slug: "launch-video"))
        // The listener's answers find the project's review by the id prefix.
        let thread = try #require(window.threads.last)
        #expect(await ask(.reply(thread: thread.id.text, text: "Slowed it"), server).ok)
        #expect(window.threads.last?.messages.last?.text == "Slowed it")
        // wait --video on a project's version binds to the project too.
        #expect(try await app.listenedReview(video: Self.cut1.path) == .project(slug: "launch-video"))
        app.listeners.stop()
    }

    @Test("the home screen shows the projects, the latest version's file and when each was opened")
    func home() async throws {
        defer { cleanUp() }
        let (app, window, server) = try await run()
        #expect(app.homeProjects.isEmpty)
        #expect(await ask(.projectNew(slug: "launch-video", path: Self.cut1.path, title: "Launch video"), server).ok)
        #expect(await ask(.projectAdd(slug: "launch-video", path: Self.cut2.path), server).ok)
        await window.goHome()
        let projects = app.homeProjects
        #expect(projects.map(\.title) == ["Launch video"])
        #expect(projects.first?.versions == 2)
        #expect(projects.first?.latestPath == Self.cut2.path)
        #expect(projects.first?.available == true)
        #expect(projects.first?.openedAt != nil)
        #expect(StageContent(window) == .home)
        let state = try object(await ask(.state, server, json: true).output)
        #expect((state["projects"] as? [[String: Any]])?.map { $0["slug"] as? String } == ["launch-video"])
        #expect(ProjectCard.detail(try #require(projects.first), now: Date()) == "2 versions, opened just now")
        app.listeners.stop()
    }
}
