import Foundation
@testable import ReviewApp
import ReviewCore
import ReviewLease
import ReviewStore
import ReviewWire
import Testing

/// The demo in the same window: one model on the person's support folder
/// switches to a demo folder and back, through the methods "Try the Demo",
/// the Open panel, a drop and going home call. No window and no socket.
@Suite("The demo in the same window", .serialized)
struct DemoTests {
    nonisolated static let listener = Holder(key: "listener-1", name: "Mate", place: "/shop")

    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("havooch-tests-\(UUID().uuidString)", isDirectory: true)
    var person: URL { root.appendingPathComponent("person", isDirectory: true) }
    var demo: URL { root.appendingPathComponent("Havooch Demo", isDirectory: true) }

    private func cleanUp() {
        try? FileManager.default.removeItem(at: root)
    }

    /// The app on the person's folder, moved there as a check's scratch
    /// folder is, or on the launch `environment` names, with the demo
    /// folder under the test's root, and the server in front of it.
    private func run(environment: [String: String]? = nil) -> (AppModel, ControlServer) {
        let model = AppModel(
            environment: environment ?? [SupportFolder.overrideVariable: person.path], speech: SlowRecognizer(), demoFolder: demo
        )
        let server = ControlServer(
            socket: URL(fileURLWithPath: "/nowhere/control.sock"), app: model, listeners: { model.listeners },
            screenshotter: ControlServerTests.FakeScreenshotter(), quit: {}
        )
        return (model, server)
    }

    /// The person's own video: a copy of the fixture, so it isn't the demo's file.
    private func ownVideo() throws -> URL {
        let folder = root.appendingPathComponent("Movies", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let copy = folder.appendingPathComponent("mine.mp4")
        try FileManager.default.copyItem(at: MessageTests.fixture, to: copy)
        return copy
    }

    private func reviewFile(in support: URL) throws -> URL {
        let hash = try #require(ContentHash.of(MessageTests.fixture))
        return SupportLayout(root: support).reviewFile(hash)
    }

    private func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    private func eventually(_ condition: () -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(10)
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test("entering the demo switches the run to the demo folder and opens the video there, in the same model")
    func enter() async throws {
        defer { cleanUp() }
        let (model, _) = run()
        // A moved support folder with no demo mark is a normal run on it.
        #expect(!model.isDemo)
        #expect(!model.state().app.demo)

        try await model.enterDemo(MessageTests.fixture)

        #expect(model.isDemo)
        #expect(model.support.path == demo.path)
        #expect(model.state().app.demo)
        #expect(model.state().app.support == demo.path)
        #expect(model.video?.url == MessageTests.fixture.standardizedFileURL)
    }

    @Test("demo threads stay in the demo folder, out of the person's")
    func threadsStayOut() async throws {
        defer { cleanUp() }
        let (model, _) = run()
        try await model.enterDemo(MessageTests.fixture)

        _ = try await model.addMessage(text: "On the demo", at: 2)

        #expect(exists(try reviewFile(in: demo)))
        #expect(!exists(try reviewFile(in: person)))
        #expect(!exists(SupportLayout(root: person).recentsFile))
    }

    @Test("leaving the demo closes its video and puts the run back on the person's folder, which has none of its threads")
    func leave() async throws {
        defer { cleanUp() }
        let (model, _) = run()
        try await model.enterDemo(MessageTests.fixture)
        _ = try await model.addMessage(text: "On the demo", at: 2)

        await model.leaveDemo()

        #expect(!model.isDemo)
        #expect(model.video == nil)
        #expect(model.threads.isEmpty)
        #expect(model.support.path == person.path)
        #expect(model.engine.duration == 0)

        // The same content on the person's data starts with no threads.
        try await model.open(try ownVideo())
        #expect(model.frameThreads.isEmpty)
        #expect(model.threads.flatMap(\.messages).isEmpty)
    }

    @Test("the demo folder keeps its threads for the next demo")
    func demoKeepsThreads() async throws {
        defer { cleanUp() }
        let (model, _) = run()
        try await model.enterDemo(MessageTests.fixture)
        _ = try await model.addMessage(text: "On the demo", at: 2)
        await model.leaveDemo()

        try await model.enterDemo(MessageTests.fixture)

        #expect(model.frameThreads.count == 1)
    }

    @Test("a video opened from the panel or by a drop during the demo leaves the demo first and opens on the person's data")
    func openDuringDemo() async throws {
        defer { cleanUp() }
        let (model, _) = run()
        try await model.enterDemo(MessageTests.fixture)
        let mine = try ownVideo()

        model.openForPerson(mine)
        await eventually { model.video?.url == mine.standardizedFileURL }

        #expect(model.video?.url == mine.standardizedFileURL)
        #expect(!model.isDemo)
        #expect(model.support.path == person.path)
        #expect(Library(layout: SupportLayout(root: person)).recents().map(\.path) == [mine.standardizedFileURL.path])
        #expect(Library(layout: SupportLayout(root: demo)).recents().map(\.path) == [MessageTests.fixture.standardizedFileURL.path])
    }

    @Test("the recent videos are the ones of the data the run is on, and the demo's never join the person's")
    func recentsFollowTheData() async throws {
        defer { cleanUp() }
        let (model, _) = run()
        let mine = try ownVideo()
        try await model.open(mine)
        #expect(model.recents.map(\.path) == [mine.standardizedFileURL.path])

        try await model.enterDemo(MessageTests.fixture)
        #expect(model.recents.map(\.path) == [MessageTests.fixture.standardizedFileURL.path])

        await model.leaveDemo()
        #expect(model.recents.map(\.path) == [mine.standardizedFileURL.path])
    }

    @Test("the theme stays on the person's data during the demo")
    func themeStays() async throws {
        defer { cleanUp() }
        let (model, _) = run()
        try await model.enterDemo(MessageTests.fixture)

        _ = try model.setTheme("Default Dark")

        let pinned = try String(contentsOf: person.appendingPathComponent("config/config.toml"), encoding: .utf8)
        #expect(pinned.contains("theme = \"Default Dark\""))
        #expect(!exists(demo.appendingPathComponent("config")))
    }

    @Test("the control socket stays on the person's folder, and no demo pointer is recorded")
    func socketStays() async throws {
        defer { cleanUp() }
        let (model, _) = run()

        try await model.enterDemo(MessageTests.fixture)

        #expect(model.launchSupport.path == person.path)
        #expect(ControlSocket.locate(support: person).path == ControlSocket.url(in: model.launchSupport).path)
        #expect(DemoPointer.recorded(in: person) == nil)
    }

    @Test("a listener's commands reach the data the run is on: the demo's sends during the demo, none after it")
    func listenerFollows() async throws {
        defer { cleanUp() }
        let (model, server) = run()
        try await model.enterDemo(MessageTests.fixture)
        _ = try await model.addMessage(text: "On the demo", at: 2)
        let send = try await model.sendQueue()

        let taken = await server.replyWritten(to: ControlRequest.wait(timeoutSeconds: 0).sent(by: Self.listener, json: true)).reply
        #expect(taken.ok)
        #expect(taken.output.contains(send.id))
        #expect(try await listener(server)["takenSends"] as? Int == 1)

        await model.leaveDemo()

        #expect(try await listener(server)["takenSends"] as? Int == 0)
        #expect(try await listener(server)["pendingSends"] as? Int == 0)
    }

    @Test("a send handed out before the demo was left is taken in the demo's outbox once its reply is written")
    func writtenAfterLeaving() async throws {
        defer { cleanUp() }
        let (model, server) = run()
        try await model.enterDemo(MessageTests.fixture)
        _ = try await model.addMessage(text: "On the demo", at: 2)
        _ = try await model.sendQueue()
        let answer = await server.reply(to: ControlRequest.wait(timeoutSeconds: 0).sent(by: Self.listener, json: true))
        #expect(answer.delivered != nil)

        await model.leaveDemo()
        server.written(answer)
        try await model.enterDemo(MessageTests.fixture)

        #expect(try await listener(server)["takenSends"] as? Int == 1)
        #expect(try await listener(server)["pendingSends"] as? Int == 0)
    }

    @Test("a demo video that doesn't open leaves the demo again")
    func demoThatDoesNotOpen() async throws {
        defer { cleanUp() }
        let (model, _) = run()

        await #expect(throws: AppRefusal.self) { try await model.enterDemo(root.appendingPathComponent("missing.mp4")) }

        #expect(!model.isDemo)
        #expect(model.support.path == person.path)
    }

    @Test("a video still opening when the run switches to the demo is refused, and never lands on the demo's data")
    func openAcrossSwitch() async throws {
        defer { cleanUp() }
        let (model, _) = run()
        let mine = try ownVideo()
        // The refusal the open ended with, if any.
        let opening = Task { () async -> String? in
            do throws(AppRefusal) {
                try await model.open(mine)
                return nil
            } catch {
                return error.reason
            }
        }
        await Task.yield()

        try await model.enterDemo(MessageTests.fixture)

        #expect(await opening.value?.contains("switched") == true)
        #expect(model.video?.url == MessageTests.fixture.standardizedFileURL)
        #expect(Library(layout: SupportLayout(root: demo)).recents().map(\.path) == [MessageTests.fixture.standardizedFileURL.path])
    }

    /// The listener as `state` reports it through the server.
    private func listener(_ server: ControlServer) async throws -> [String: Any] {
        let output = await server.reply(to: ControlRequest.state.sent(by: Self.listener, json: true)).reply.output
        let state = try #require(JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any])
        return try #require(state["listener"] as? [String: Any])
    }

    @Test("a run started with app open --demo is a demo, and entering and leaving keep it on its folder")
    func demoRun() async throws {
        defer { cleanUp() }
        let folder = root.appendingPathComponent("acceptance", isDirectory: true)
        let (model, _) = run(environment: [SupportFolder.overrideVariable: folder.path, SupportFolder.demoRunVariable: "1"])
        #expect(model.isDemo)
        #expect(model.state().app.demo)

        try await model.enterDemo(MessageTests.fixture)
        #expect(model.support.path == folder.path)
        #expect(model.video != nil)

        await model.leaveDemo()
        #expect(model.isDemo)
        #expect(model.support.path == folder.path)
        #expect(!exists(demo))
    }
}
