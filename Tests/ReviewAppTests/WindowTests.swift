import Foundation
@testable import ReviewApp
import ReviewLease
import ReviewStore
import ReviewWire
import Testing

/// Any number of windows, each with one video or none (ADR 0003): which
/// window an open goes to, what each window keeps of its own, and the
/// window commands. The app model and its control server, with no scene
/// and no socket: a window made here has no AppKit window.
@Suite("Windows", .serialized)
struct WindowTests {
    static let agent = Holder(key: "agent-1", name: "Claude Code", place: "/Users/me/shop")
    /// A second video, with other content than `MessageTests.fixture`.
    static let launch = MessageTests.fixture.deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("launch/havooch-demo.mp4")

    let support = FileManager.default.temporaryDirectory
        .appendingPathComponent("havooch-tests-\(UUID().uuidString)", isDirectory: true)

    private func cleanUp() {
        try? FileManager.default.removeItem(at: support)
    }

    /// The app on a fresh folder with its first window, as a launch shows
    /// it, and the server in front of it. `fronts` counts the times the app
    /// came to the front.
    private func run() -> (app: AppModel, first: WindowModel, server: ControlServer, fronts: Fronts) {
        let app = AppModel(environment: [SupportFolder.overrideVariable: support.path, MutedRun.variable: "1"], speech: SlowRecognizer())
        let fronts = Fronts()
        app.bringToFront = { _ in fronts.count += 1 }
        let first = app.makeWindow()
        let server = ControlServer(
            socket: URL(fileURLWithPath: "/nowhere/control.sock"), app: app, listeners: { app.listeners },
            screenshotter: ControlServerTests.FakeScreenshotter(), quit: {}
        )
        return (app, first, server, fronts)
    }

    final class Fronts {
        var count = 0
    }

    private func send(_ request: ControlRequest, _ server: ControlServer, window: String? = nil, json: Bool = false) async -> ControlReply {
        await server.reply(to: ControlMessage(request, holder: Self.agent, json: json, window: window).encoded()).reply
    }

    private func object(_ output: String) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any])
    }

    // MARK: - Where a video opens

    @Test("havooch open takes the empty key window, makes a new one for another video, and brings the holder forward for an open one")
    func openFindsItsWindow() async throws {
        defer { cleanUp() }
        let (app, first, server, fronts) = run()

        #expect(await send(.open(path: MessageTests.fixture.path), server).ok)
        #expect(app.windows.windows.count == 1)
        #expect(first.video?.url == MessageTests.fixture.standardizedFileURL)

        let reply = await send(.open(path: Self.launch.path), server)
        #expect(reply.ok)
        #expect(reply.output.hasSuffix(") in w2, playing\n"))
        #expect(app.windows.windows.map(\.id) == ["w1", "w2"])
        let second = try #require(app.windows.window("w2"))
        #expect(second.video?.url == Self.launch.standardizedFileURL)
        #expect(app.windows.key === second)

        // The first video again: its window comes forward, and no third one opens.
        first.engine.pause()
        let again = await send(.open(path: MessageTests.fixture.path), server)
        #expect(again.output.hasSuffix(") in w1, playing\n"))
        #expect(app.windows.windows.count == 2)
        #expect(app.windows.key === first)
        #expect(first.engine.isPlaying)
        #expect(fronts.count == 3)
    }

    @Test("a renamed copy of an open video is the same video: it brings its window forward")
    func copyIsTheSameVideo() async throws {
        defer { cleanUp() }
        let (app, first, _, _) = run()
        try await first.open(MessageTests.fixture)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        let copy = support.appendingPathComponent("renamed.mp4")
        try FileManager.default.copyItem(at: MessageTests.fixture, to: copy)

        let window = try await app.openInFront(copy)

        #expect(window === first)
        #expect(app.windows.windows.count == 1)
    }

    @Test("a file that doesn't play opens no window")
    func refusedOpensNoWindow() async throws {
        defer { cleanUp() }
        let (app, first, server, _) = run()
        try await first.open(MessageTests.fixture)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        let notes = support.appendingPathComponent("notes.mp4")
        try Data("not a video".utf8).write(to: notes)

        #expect(!(await send(.open(path: notes.path), server)).ok)
        #expect(app.windows.windows.count == 1)
    }

    @Test("a window never opens a video another window holds: the operator is told which window has it")
    func oneVideoOneWindow() async throws {
        defer { cleanUp() }
        let (app, first, server, _) = run()
        try await first.open(MessageTests.fixture)
        let second = app.newWindow()

        let reply = await send(.playerOpen(path: MessageTests.fixture.path), server, window: second.id)

        #expect(reply == .refused("sample.mp4 is open in window w1; one video opens in one window"))
        #expect(second.video == nil)
        #expect(first.video != nil)
    }

    @Test("the Open panel and a recent card in a window bring forward the window that holds the video")
    func personOpenFocusesTheHolder() async throws {
        defer { cleanUp() }
        let (app, first, _, _) = run()
        try await first.open(MessageTests.fixture)
        let second = app.newWindow()
        #expect(app.windows.key === second)

        second.openForPerson(MessageTests.fixture)
        let deadline = ContinuousClock.now + .seconds(10)
        while app.windows.key !== first, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(app.windows.key === first)
        #expect(second.video == nil)
    }

    // MARK: - What each window keeps

    @Test("each window keeps its own player, popover, queue, sidebar and notices")
    func eachWindowHasItsOwn() async throws {
        defer { cleanUp() }
        let (app, first, _, _) = run()
        let second = app.newWindow()
        try await first.open(MessageTests.fixture)
        try await second.open(Self.launch)

        try await first.seek(to: 2)
        _ = try await first.addMessage(text: "Tighten the intro", at: 1, region: nil, thread: nil)
        _ = try first.openPopover(text: "half written", region: nil)
        try await second.seek(to: 3)
        _ = try await second.addMessage(text: "Brighter here", at: 3, region: nil, thread: nil)
        _ = try await second.addMessage(text: "And here", at: 4, region: nil, thread: nil)

        #expect(abs(first.engine.time - 1) < 0.1)
        #expect(abs(second.engine.time - 4) < 0.1)
        #expect(first.queuedCount == 1)
        #expect(second.queuedCount == 2)
        #expect(first.draft?.text == "half written")
        #expect(second.draft == nil)
        #expect(first.state().queue.count == 1)
        #expect(second.state().queue.count == 2)

        _ = try await second.showThread("2")
        #expect(second.state().sidebar?.thread != nil)
        #expect(first.state().sidebar?.thread == nil)

        _ = try await second.sendQueue()
        // The agent's reply on the second video shows in the second window only.
        let thread = try #require(second.threads.first { $0.number == 1 })
        _ = try app.listeners.reply(on: thread.id.text, text: "On it")
        #expect(second.notices.count == 1)
        #expect(first.notices.isEmpty)
    }

    @Test("a send carries only its own window's queue")
    func sendIsPerWindow() async throws {
        defer { cleanUp() }
        let (app, first, _, _) = run()
        let second = app.newWindow()
        try await first.open(MessageTests.fixture)
        try await second.open(Self.launch)
        _ = try await first.addMessage(text: "One", at: 1, region: nil, thread: nil)
        _ = try await second.addMessage(text: "Two", at: 2, region: nil, thread: nil)

        let send = try await first.sendQueue()

        #expect(send.messageIds.count == 1)
        #expect(first.queuedCount == 0)
        #expect(second.queuedCount == 1)
    }

    // MARK: - Closing

    @Test("closing a window pauses its video, keeps its position, and leaves the other windows and the app")
    func closeOne() async throws {
        defer { cleanUp() }
        let (app, first, server, _) = run()
        let second = app.newWindow()
        try await first.open(MessageTests.fixture)
        try await second.open(Self.launch)
        try await first.seek(to: 2)
        try first.play()

        let reply = await send(.windowClose, server, window: "w1")

        #expect(reply == .done("w1 closed\n"))
        #expect(!first.engine.isPlaying)
        #expect(app.windows.windows.map(\.id) == ["w2"])
        #expect(app.recents.first { $0.contentHash == first.video?.contentHash }?.position ?? 0 >= 2)
        // The next window's id is new.
        #expect(app.newWindow().id == "w3")
    }

    @Test("with every window closed the app runs on: state says so, and a command that shows something makes a window")
    func noWindow() async throws {
        defer { cleanUp() }
        let (app, first, server, _) = run()
        app.windowClosed(first)

        let state = try object(await send(.state, server, json: true).output)
        #expect(state["screen"] as? String == "none")
        #expect(state["window"] is NSNull)
        #expect((state["windows"] as? [Any])?.isEmpty == true)
        #expect(await send(.playerPlay, server) == .refused("no window is open; open one with `havooch window new`"))

        let opened = await send(.playerOpen(path: MessageTests.fixture.path), server)
        #expect(opened.ok)
        #expect(opened.output.hasSuffix(" in w2\n"))
        #expect(app.windows.windows.count == 1)
    }

    // MARK: - The window commands

    @Test("window new, list and close, and --window on an operator command")
    func windowCommands() async throws {
        defer { cleanUp() }
        let (app, first, server, _) = run()
        try await first.open(MessageTests.fixture)

        #expect(await send(.windowNew, server) == .done("w2 opened, showing home\n"))
        let list = await send(.windowList, server)
        #expect(list.output.hasPrefix("windows: 2\n  w1 player off screen sample.mp4 "))
        #expect(list.output.hasSuffix("  w2 key home off screen\n"))

        let json = try object(await send(.windowList, server, json: true).output)
        let windows = try #require(json["windows"] as? [[String: Any]])
        #expect(windows.map { $0["id"] as? String } == ["w1", "w2"])
        #expect(windows.map { $0["key"] as? Bool } == [false, true])
        #expect((windows[0]["video"] as? [String: Any])?["title"] as? String == "sample.mp4")
        #expect(windows[1]["video"] is NSNull)

        // Without --window the key window, w2, has no video; with it, w1 plays.
        #expect(!(await send(.playerPlay, server)).ok)
        #expect(await send(.playerPlay, server, window: "w1").ok)
        #expect(first.engine.isPlaying)
        #expect(await send(.playerPlay, server, window: "w9") == .refused("no window `w9`; the windows are w1, w2"))

        // state names its window and lists them all.
        let state = try object(await send(.state, server, window: "w1", json: true).output)
        #expect(state["window"] as? String == "w1")
        #expect(state["screen"] as? String == "player")
        #expect((state["windows"] as? [Any])?.count == 2)
        #expect(await send(.state, server).output.contains("\nwindow: w2\n"))

        #expect(await send(.windowClose, server) == .done("w2 closed\n"))
        #expect(app.windows.windows.map(\.id) == ["w1"])
        #expect(app.windows.key === first)
    }

    @Test("window list is free; window new and close take the lease")
    func roles() {
        #expect(ControlRequest.windowList.role == .free)
        #expect(ControlRequest.windowNew.role == .operator)
        #expect(ControlRequest.windowClose.role == .operator)
    }

    @Test("a scene takes the window made for it, else a new empty one")
    func scenesTakeTheirWindows() async throws {
        defer { cleanUp() }
        let (app, first, _, _) = run()
        var opened: [WindowTarget?] = []
        app.windows.openScene = { opened.append($0) }

        let made = app.newWindow()
        #expect(opened == [nil])
        #expect(app.sceneAppeared(target: nil) === made)
        // A scene with no window waiting (the Dock icon, a launch) gets a new one.
        let fresh = app.sceneAppeared(target: nil)
        #expect(fresh !== made)
        #expect(fresh !== first)
        #expect(fresh.video == nil)
        #expect(app.windows.windows.count == 3)
    }

    @Test("a target is its video's content: two paths of one video are one target")
    func targetIsTheContent() {
        let one = WindowTarget.video(contentHash: "abc", path: "/a.mp4")
        let moved = WindowTarget.video(contentHash: "abc", path: "/b/a copy.mp4")
        #expect(one == moved)
        #expect(Set([one, moved]).count == 1)
        #expect(one != .video(contentHash: "def", path: "/a.mp4"))
    }
}
