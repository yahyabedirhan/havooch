import Foundation
@testable import ReviewApp
import ReviewLease
import ReviewStore
import ReviewWire
import Testing

/// `havooch open` in the app: the person's open, playing and in front,
/// through the control server as the command sends it. No window and no
/// socket; the launch and the activation are the app's (`bringToFront`).
@Suite("havooch open in the app", .serialized)
struct OpenInFrontTests {
    static let agent = Holder(key: "agent-1", name: "Claude Code", place: "/Users/me/shop")

    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("havooch-tests-\(UUID().uuidString)", isDirectory: true)
    var person: URL { root.appendingPathComponent("person", isDirectory: true) }
    var demo: URL { root.appendingPathComponent("Havooch Demo", isDirectory: true) }

    private func cleanUp() {
        try? FileManager.default.removeItem(at: root)
    }

    /// The app on the person's folder, the demo's under the test's root,
    /// counting each time it's brought to the front.
    private func run() -> (WindowModel, ControlServer, Fronts) {
        let model = AppModel(
            environment: [SupportFolder.overrideVariable: person.path], speech: SlowRecognizer(), demoFolder: demo,
            demoVideo: MessageTests.fixture
        ).makeWindow()
        let fronts = Fronts()
        model.app.bringToFront = { _ in fronts.count += 1 }
        let server = ControlServer(
            socket: URL(fileURLWithPath: "/nowhere/control.sock"), app: model.app, listeners: { model.listeners },
            screenshotter: ControlServerTests.FakeScreenshotter(), quit: {}
        )
        return (model, server, fronts)
    }

    final class Fronts {
        var count = 0
    }

    /// A copy of the fixture under the test's root, named `name`.
    private func video(_ name: String) throws -> URL {
        let folder = root.appendingPathComponent("Movies", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let copy = folder.appendingPathComponent(name)
        try FileManager.default.copyItem(at: MessageTests.fixture, to: copy)
        return copy
    }

    /// A file named like a video that isn't one.
    private func notAVideo() throws -> URL {
        let folder = root.appendingPathComponent("Movies", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("notes.mp4")
        try Data("These are notes, not a video.".utf8).write(to: file)
        return file
    }

    private func send(_ request: ControlRequest, to server: ControlServer) async -> ControlReply {
        await server.reply(to: ControlMessage(request, holder: Self.agent).encoded()).reply
    }

    @Test("open shows the video playing, brings the app to the front, and takes no lease")
    func opensPlayingInFront() async throws {
        defer { cleanUp() }
        let (model, server, fronts) = run()
        let cut = try video("cut2.mp4")
        let reply = await send(.open(path: cut.path), to: server)
        #expect(reply.ok)
        #expect(reply.output.hasPrefix("opened cut2.mp4 ("))
        #expect(reply.output.hasSuffix(") in w1, playing\n"))
        #expect(model.video?.url == cut.standardizedFileURL)
        #expect(model.engine.isPlaying)
        #expect(fronts.count == 1)
        #expect(server.lease.current(at: Date()) == nil)
        #expect(server.indicator.shown(at: Date()) == nil)
    }

    @Test("a file that doesn't play is refused and nothing opens: the open video stays, paused where it was")
    func refusesUnplayable() async throws {
        defer { cleanUp() }
        let (model, server, fronts) = run()
        let cut = try video("cut1.mp4")
        try await model.open(cut)
        let bad = try notAVideo()
        let reply = await send(.open(path: bad.path), to: server)
        #expect(!reply.ok)
        #expect(reply.error.hasPrefix("can't play \(bad.path)"))
        #expect(model.video?.url == cut.standardizedFileURL)
        #expect(!model.engine.isPlaying)
        #expect(fronts.count == 0)

        let missing = root.appendingPathComponent("missing.mp4").path
        #expect(await send(.open(path: missing), to: server) == .refused("no video file at \(missing)"))
        #expect(fronts.count == 0)
    }

    @Test("open leaves an in-app demo for the person's own data, as the Open panel does; a refused one stays in the demo")
    func leavesTheDemo() async throws {
        defer { cleanUp() }
        let (model, server, _) = run()
        try await model.openDemo()
        #expect(model.isInAppDemo)

        _ = await send(.open(path: try notAVideo().path), to: server)
        #expect(model.isInAppDemo)

        let cut = try video("cut2.mp4")
        #expect(await send(.open(path: cut.path), to: server).ok)
        #expect(!model.isInAppDemo)
        #expect(model.support.standardizedFileURL == person.standardizedFileURL)
        #expect(model.video?.url == cut.standardizedFileURL)
    }

    @Test("player open stays the operator's leased open: paused, not in front, and it takes the lease")
    func playerOpenStaysLeased() async throws {
        defer { cleanUp() }
        let (model, server, fronts) = run()
        let cut = try video("cut2.mp4")
        #expect(await send(.playerOpen(path: cut.path), to: server).ok)
        #expect(!model.engine.isPlaying)
        #expect(fronts.count == 0)
        #expect(server.lease.current(at: Date())?.holder == Self.agent)
        #expect(ControlRequest.playerOpen(path: cut.path).role == .operator)
    }
}
