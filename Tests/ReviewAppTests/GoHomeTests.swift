import Foundation
@testable import ReviewApp
import ReviewLease
import ReviewStore
import ReviewWire
import Testing

/// Going home from the player: `AppModel.goHome()`, which the Havooch mark
/// in the header, File > Close Video and `app home` call, and `app demo`,
/// which runs "Try the Demo". One model on a temporary support folder, with
/// the server in front of it. No window: the header and the menu are
/// checked through app control.
@Suite("Going home from the player", .serialized)
struct GoHomeTests {
    nonisolated static let agent = Holder(key: "agent-1", name: "Claude Code", place: "/work")

    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("havooch-tests-\(UUID().uuidString)", isDirectory: true)
    var person: URL { root.appendingPathComponent("person", isDirectory: true) }
    var demo: URL { root.appendingPathComponent("Havooch Demo", isDirectory: true) }

    private func cleanUp() {
        try? FileManager.default.removeItem(at: root)
    }

    /// The app on the person's folder, with the fixture as its bundled demo
    /// video unless `demoVideo` says otherwise, and the server in front of
    /// it. `shown` counts the times the model asked to show the window.
    private func run(
        environment: [String: String]? = nil, demoVideo: URL? = MessageTests.fixture
    ) -> (model: AppModel, server: ControlServer, shown: Counter) {
        let model = AppModel(
            environment: environment ?? [SupportFolder.overrideVariable: person.path], speech: SlowRecognizer(),
            demoFolder: demo, demoVideo: demoVideo
        )
        let shown = Counter()
        model.showWindow = { shown.count += 1 }
        let server = ControlServer(
            socket: URL(fileURLWithPath: "/nowhere/control.sock"), app: model, listeners: { model.listeners },
            screenshotter: ControlServerTests.FakeScreenshotter(), quit: {}
        )
        return (model, server, shown)
    }

    final class Counter {
        var count = 0
    }

    /// Counts observation's change calls, which come on a `Sendable` closure.
    nonisolated final class Changes: @unchecked Sendable {
        var count = 0
    }

    /// The person's own video: a copy of the fixture, so it isn't the demo's file.
    private func ownVideo() throws -> URL {
        let folder = root.appendingPathComponent("Movies", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let copy = folder.appendingPathComponent("mine.mp4")
        try FileManager.default.copyItem(at: MessageTests.fixture, to: copy)
        return copy
    }

    private func send(_ request: ControlRequest, _ server: ControlServer, json: Bool = false) async -> ControlReply {
        await server.reply(to: request.sent(by: Self.agent, json: json)).reply
    }

    private func object(_ output: String) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any])
    }

    // MARK: - goHome

    @Test("going home saves the position, closes the video and shows home with the video on it")
    func goHome() async throws {
        defer { cleanUp() }
        let (model, _, shown) = run()
        let mine = try ownVideo()
        try await model.open(mine)
        try await model.seek(to: 2.5)
        let before = shown.count

        await model.goHome()

        #expect(model.video == nil)
        #expect(model.engine.duration == 0)
        #expect(model.threads.isEmpty)
        #expect(model.recents.map(\.path) == [mine.standardizedFileURL.path])
        #expect(model.recents.map(\.position) == [2.5])
        #expect(StageContent(model) == .home)
        #expect(model.state().screen == .home)
        #expect(shown.count == before + 1)
        #expect(!model.isDemo)
    }

    @Test("going home with no video changes nothing but shows the window")
    func goHomeWithNoVideo() async {
        defer { cleanUp() }
        let (model, _, shown) = run()

        await model.goHome()

        #expect(model.video == nil)
        #expect(model.recents.isEmpty)
        #expect(model.state().screen == .home)
        #expect(shown.count == 1)
    }

    @Test("going home again tells the home screen to read the recent videos, so a moved file's card turns unavailable")
    func goHomeRereadsTheRecentVideos() async throws {
        defer { cleanUp() }
        let (model, _, _) = run()
        let mine = try ownVideo()
        try await model.open(mine)
        await model.goHome()
        try FileManager.default.moveItem(at: mine, to: root.appendingPathComponent("moved.mp4"))
        let changed = Changes()
        withObservationTracking { _ = model.recents } onChange: { changed.count += 1 }

        await model.goHome()

        #expect(changed.count == 1)
        #expect(model.recents.map(\.available) == [false])
    }

    @Test("the app coming to the front tells the home screen to read the recent videos again")
    func refreshRecents() async throws {
        defer { cleanUp() }
        let (model, _, _) = run()
        try await model.open(ownVideo())
        await model.goHome()
        let changed = Changes()
        withObservationTracking { _ = model.recents } onChange: { changed.count += 1 }

        model.refreshRecents()

        #expect(changed.count == 1)
    }

    @Test("going home during the demo leaves it: the run is back on the person's data, with the demo's position on the demo's list")
    func goHomeLeavesTheDemo() async throws {
        defer { cleanUp() }
        let (model, _, _) = run()
        let mine = try ownVideo()
        try await model.open(mine)
        try await model.openDemo()
        try await model.seek(to: 3)
        #expect(model.isDemo)

        await model.goHome()

        #expect(!model.isDemo)
        #expect(model.video == nil)
        #expect(model.support.path == person.path)
        #expect(model.recents.map(\.path) == [mine.standardizedFileURL.path])
        #expect(Library(layout: SupportLayout(root: demo)).recents().map(\.position) == [3])
    }

    @Test("going home on a run started with app open --demo stays on its folder")
    func goHomeOnADemoRun() async throws {
        defer { cleanUp() }
        let folder = root.appendingPathComponent("acceptance", isDirectory: true)
        let (model, _, _) = run(environment: [SupportFolder.overrideVariable: folder.path, SupportFolder.demoRunVariable: "1"])
        try await model.openDemo()

        await model.goHome()

        #expect(model.video == nil)
        #expect(model.isDemo)
        #expect(model.support.path == folder.path)
    }

    @Test("going home does what opening another video does: popover words are queued, composer words go, the queue stays")
    func goHomeWithWords() async throws {
        defer { cleanUp() }
        let (model, _, _) = run()
        let mine = try ownVideo()
        try await model.open(mine)
        _ = try await model.addMessage(text: "Queued", at: 1)
        try await model.seek(to: 2)
        _ = try model.openPopover(text: "In the popover", region: nil)
        _ = try model.compose(text: "In the composer", region: nil, general: true)

        await model.goHome()

        #expect(model.draft == nil)
        #expect(model.composerDrafts.isEmpty)
        try await model.open(mine)
        let queued = model.threads.flatMap(\.messages).filter { $0.state == .queued }.map(\.text)
        #expect(Set(queued) == ["Queued", "In the popover"])
        #expect(model.composerText.isEmpty)
    }

    // MARK: - app home, app demo and screen

    @Test("app home goes home and says so; state then reports the home screen")
    func appHome() async throws {
        defer { cleanUp() }
        let (model, server, shown) = run()
        try await model.open(try ownVideo())
        #expect(model.state().screen == .player)
        #expect(try object(await send(.state, server, json: true).output)["screen"] as? String == "player")
        let before = shown.count

        let reply = await send(.appHome, server)

        #expect(reply == .done("home, 1 recent video, your data\n"))
        #expect(model.video == nil)
        #expect(shown.count == before + 1)
        #expect(await send(.state, server).output.contains("\nscreen: home\n"))
        let json = try object(await send(.appHome, server, json: true).output)
        #expect(json["screen"] as? String == "home")
        #expect((json["app"] as? [String: Any])?["demo"] as? Bool == false)
    }

    @Test("state reports home on the first launch's empty screen too")
    func emptyIsHome() async throws {
        defer { cleanUp() }
        let (model, server, _) = run()
        #expect(StageContent(model) == .empty)
        #expect(try object(await send(.state, server, json: true).output)["screen"] as? String == "home")
    }

    @Test("app demo runs the demo in the same model, as Try the Demo does, and app home leaves it")
    func appDemo() async throws {
        defer { cleanUp() }
        let (model, server, shown) = run()

        let reply = await send(.appDemo, server)

        #expect(reply.ok)
        #expect(reply.output.hasPrefix("opened sample.mp4 ("))
        #expect(reply.output.hasSuffix(") on demo data\n"))
        #expect(model.isDemo)
        #expect(model.support.path == demo.path)
        #expect(model.video?.url == MessageTests.fixture.standardizedFileURL)
        #expect(shown.count >= 1)
        let state = try object(await send(.state, server, json: true).output)
        #expect(state["screen"] as? String == "player")
        #expect((state["app"] as? [String: Any])?["demo"] as? Bool == true)

        #expect(await send(.appHome, server) == .done("home, 0 recent videos, your data\n"))
        #expect(!model.isDemo)
        #expect(model.support.path == person.path)
    }

    @Test("app demo in a build with no bundled demo video is refused, and nothing changes")
    func appDemoWithoutVideo() async {
        defer { cleanUp() }
        let (model, server, _) = run(demoVideo: nil)

        let reply = await send(.appDemo, server)

        #expect(reply == .refused("this build has no bundled demo video; run `make bundle`"))
        #expect(!model.isDemo)
        #expect(model.video == nil)
    }

    @Test("app home and app demo need the lease")
    func needTheLease() async throws {
        defer { cleanUp() }
        let (model, server, _) = run()
        try await model.open(try ownVideo())
        let other = Holder(key: "agent-2", name: "Codex", place: "/elsewhere")
        _ = await send(.controlTake(waitSeconds: nil), server)

        let home = await server.reply(to: ControlRequest.appHome.sent(by: other)).reply
        let demoReply = await server.reply(to: ControlRequest.appDemo.sent(by: other)).reply

        #expect(!home.ok)
        #expect(!demoReply.ok)
        #expect(model.video != nil)
        #expect(!model.isDemo)
    }
}
