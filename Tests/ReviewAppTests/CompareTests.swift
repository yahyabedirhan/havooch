import Foundation
@testable import ReviewApp
import ReviewCore
import ReviewLease
import ReviewStore
import ReviewWire
import Testing

/// The comparison's rules (E11, compare-control V4), pure: it opens on
/// the previous version and the one on screen, a side given the other
/// side's version swaps them, and the slider stays inside the picture.
@Suite("The compare session")
struct CompareSessionTests {
    @Test("Compare opens on the previous version and the one on screen", arguments: [
        (2, 2 as Int?, 1, 2), (5, 5, 4, 5), (5, 3, 2, 3), (5, 1, 1, 2), (5, nil, 4, 5), (3, 9, 2, 3),
    ] as [(Int, Int?, Int, Int)])
    func opening(count: Int, onScreen: Int?, left: Int, right: Int) throws {
        let session = try #require(CompareSession.opening(versions: count, onScreen: onScreen))
        #expect(session.number(.left) == left)
        #expect(session.number(.right) == right)
        #expect(session.phase == .choosing)
        #expect(session.layout == .sideBySide)
        #expect(session.showing == .left)
        #expect(session.slider == 0.5)
    }

    @Test("a project of one version has nothing to compare")
    func oneVersion() {
        #expect(CompareSession.opening(versions: 1, onScreen: 1) == nil)
        #expect(CompareSession.opening(versions: 0, onScreen: nil) == nil)
    }

    @Test("picking the version on the other side swaps the sides, and a version is never compared with itself")
    func pickSwaps() throws {
        var session = try #require(CompareSession.opening(versions: 5, onScreen: 5))
        session.picker = CompareSession.SidePicker(side: .left)
        session.pick(1, for: .left)
        #expect((session.number(.left), session.number(.right)) == (1, 5))
        #expect(session.picker == nil)
        session.pick(1, for: .right)
        #expect((session.number(.left), session.number(.right)) == (5, 1))
        session.pick(3, for: .right)
        #expect((session.number(.left), session.number(.right)) == (5, 3))
        session.swap()
        #expect((session.number(.left), session.number(.right)) == (3, 5))
        #expect(session.side(of: 3) == .left)
        #expect(session.side(of: 5) == .right)
        #expect(session.side(of: 4) == nil)
    }

    @Test("the slider stays from 0 to 1, and the names and words follow the layout")
    func sliderAndWords() throws {
        var session = try #require(CompareSession.opening(versions: 2, onScreen: 2))
        session.slide(to: 1.4)
        #expect(session.slider == 1)
        session.slide(to: -2)
        #expect(session.slider == 0)
        session.slide(to: .nan)
        #expect(session.slider == 0)
        session.slide(to: 0.42)
        #expect(session.slider == 0.42)
        #expect(session.action == "Show side by side")
        session.layout = .flip
        #expect(session.action == "Compare")
        #expect(CompareSession.name(of: .left, in: .flip) == "A")
        #expect(CompareSession.name(of: .right, in: .flip) == "B")
        #expect(CompareSession.name(of: .right, in: .slider) == "Right")
        #expect(CompareLayout.allCases.map(CompareSession.words) == ["Side by side", "Flip", "Slider"])
        // Never the stacked-layers symbol.
        #expect(CompareLayout.allCases.allSatisfy { !CompareSession.symbol($0).contains("stack") })
    }
}

/// Compare in a window (E11, L63), through the app model and its
/// control server with no scene and no socket: the popover's choice, two
/// players on one playhead, messages on the side the person picks, and
/// back to one version.
@Suite("Comparing versions", .serialized)
struct CompareTests {
    static let operatorHolder = Holder(key: "codex-1", name: "Codex", place: "/Users/me/shop")
    static let sample = MessageTests.fixture.standardizedFileURL
    static let launch = WindowTests.launch.standardizedFileURL

    let support = FileManager.default.temporaryDirectory
        .appendingPathComponent("havooch-tests-\(UUID().uuidString)", isDirectory: true)

    private func cleanUp() {
        try? FileManager.default.removeItem(at: support)
    }

    /// The app on a fresh folder with the lease held, the server in front
    /// of it, and `w1` holding the project `launch-video`: v1 the sample,
    /// v2 the launch video, then `more` copies of the sample, the last on
    /// screen.
    private func run(more: Int = 0) async throws -> (app: AppModel, window: WindowModel, server: ControlServer) {
        let app = AppModel(environment: [SupportFolder.overrideVariable: support.path], speech: SlowRecognizer())
        let window = app.makeWindow()
        try await window.open(Self.sample)
        let server = ControlServer(
            socket: URL(fileURLWithPath: "/nowhere/control.sock"), app: app, listeners: { app.listeners },
            screenshotter: ControlServerTests.FakeScreenshotter(), quit: {}
        )
        #expect(await ask(.projectNew(slug: "launch-video", path: Self.sample.path, title: "Launch video"), server).ok)
        #expect(await ask(.projectAdd(slug: "launch-video", path: Self.launch.path, label: "tighter intro"), server).ok)
        let cuts = support.appendingPathComponent("cuts", isDirectory: true)
        try FileManager.default.createDirectory(at: cuts, withIntermediateDirectories: true)
        for number in stride(from: 3, through: 2 + more, by: 1) {
            let copy = cuts.appendingPathComponent("cut\(number).mp4")
            try FileManager.default.copyItem(at: Self.sample, to: copy)
            #expect(await ask(.projectAdd(slug: "launch-video", path: copy.path, label: number == 3 ? "alt opening" : nil), server).ok)
        }
        #expect(await ask(.controlTake(waitSeconds: nil), server).ok)
        return (app, window, server)
    }

    private func ask(_ request: ControlRequest, _ server: ControlServer, json: Bool = false) async -> ControlReply {
        await server.replyWritten(to: request.sent(by: Self.operatorHolder, json: json)).reply
    }

    private func object(_ output: String) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any])
    }

    /// The window's `project.compare` in `state --json`.
    private func compare(_ server: ControlServer) async throws -> [String: Any]? {
        let state = try object(await ask(.state, server, json: true).output)
        return (state["project"] as? [String: Any])?["compare"] as? [String: Any]
    }

    @Test("compare open opens the popover on the previous version and the one on screen; the sides pick, swap and close")
    func popover() async throws {
        defer { cleanUp() }
        let (app, window, server) = try await run(more: 2)
        #expect(window.versionNumber == 4)
        #expect(window.canCompare)
        #expect(try await compare(server) == nil)

        let opened = await ask(.compareOpen, server)
        #expect(opened.output == "compare: popover, v3 on the left and v4 on the right, side by side\n")
        #expect(window.compare?.phase == .choosing)

        // A click on the left side opens its picker; typing searches.
        let picked = await ask(.comparePick(side: .left, query: "alt"), server)
        #expect(picked.output.hasSuffix("  picker left \"alt\": 1 match, v3 highlighted\n"))
        let shown = try #require(try await compare(server))
        let picker = try #require(shown["picker"] as? [String: Any])
        #expect(picker["side"] as? String == "left")
        #expect(picker["matches"] as? [Int] == [3])
        #expect(shown["active"] is NSNull)

        // Return picks the highlighted row; the version on the other side swaps the sides.
        window.typeCompareQuery("")
        window.moveCompareHighlight(by: 0)
        #expect(await ask(.compareSet(CompareChange(left: 1)), server).ok)
        #expect((window.compare?.number(.left), window.compare?.number(.right)) == (1, 4))
        #expect(window.compare?.picker == nil)
        #expect(await ask(.compareSet(CompareChange(right: 1)), server).output
            == "compare: popover, v4 on the left and v1 on the right, side by side\n")
        #expect(await ask(.compareSwap, server).output == "compare: popover, v1 on the left and v4 on the right, side by side\n")
        #expect(await ask(.compareSet(CompareChange(layout: .slider, slider: 0.25)), server).output
            == "compare: popover, v1 on the left and v4 on the right, slider at 25%\n")
        // The side messages go to is picked on the stage; a version outside the list is refused.
        #expect(await ask(.compareSet(CompareChange(side: .left)), server).error
            == "the side messages go to is picked on the stage, once the window compares")
        #expect(await ask(.compareSet(CompareChange(right: 9)), server).error == "the project has no v9; it has v1 to v4")

        // Escape closes the side picker, then the popover; compare exit is Cancel.
        try window.pickCompareSide(.right)
        #expect(window.escape())
        #expect(window.compare?.picker == nil)
        #expect(window.escape())
        #expect(window.compare == nil)
        #expect(await ask(.compareOpen, server).ok)
        #expect(window.compare?.number(.left) == 3)
        let cancelled = await ask(.compareExit, server)
        #expect(cancelled.output == "Compare is closed: v4 on screen in w1\n")
        #expect(await ask(.compareExit, server).output == "Compare wasn't open\n")
        #expect(await ask(.compareSwap, server).error == "Compare isn't open; `compare open` opens its popover and `compare start` compares")
        app.listeners.stop()
    }

    @Test("compare start plays both versions on one playhead, labelled by side, and compare exit returns to the right side's")
    func onePlayhead() async throws {
        defer { cleanUp() }
        let (app, window, server) = try await run()
        try await window.seek(to: 1.5)
        let started = await ask(.compareStart, server)
        #expect(started.output == "compare: v1 on the left and v2 on the right, side by side, messages go to v2 on the right\n")
        let pair = try #require(window.pair)
        #expect(window.isComparing)
        #expect(window.activeSide == .right)
        #expect(window.versionNumber == 2)
        #expect(window.companion?.url == Self.sample)
        #expect(abs(pair.left.time - 1.5) < 0.05)
        #expect(abs(pair.right.time - 1.5) < 0.05)
        #expect(!window.canCompare)
        // Only the active side is heard.
        #expect(!pair.right.player.isMuted)
        #expect(pair.left.player.isMuted)
        // The app's level is both sides'; muted, neither plays a sound.
        app.setVolume(0.3)
        #expect(pair.left.player.volume == 0.3)
        #expect(pair.right.player.volume == 0.3)
        app.mute()
        #expect(pair.left.player.volume == 0)
        #expect(pair.right.player.volume == 0)

        // One playhead: a seek moves both, play plays both, pause pauses both.
        try await window.seek(to: 0.5)
        #expect(abs(pair.left.time - 0.5) < 0.05)
        #expect(abs(pair.right.time - 0.5) < 0.05)
        try window.play()
        try await Task.sleep(for: .milliseconds(600))
        #expect(pair.left.isPlaying)
        #expect(pair.right.isPlaying)
        #expect(abs(pair.left.player.currentTime().seconds - pair.right.player.currentTime().seconds) < 0.1)
        try window.pause()
        try await Task.sleep(for: .milliseconds(100))
        #expect(!pair.left.isPlaying)
        #expect(!pair.right.isPlaying)
        #expect(abs(pair.left.player.currentTime().seconds - pair.right.player.currentTime().seconds) < 0.05)
        // The speed is both sides'.
        window.setSpeed(1.5)
        #expect(pair.left.speed == 1.5)
        #expect(pair.right.speed == 1.5)

        let state = try #require(try await compare(server))
        #expect(state["phase"] as? String == "comparing")
        #expect(state["left"] as? Int == 1)
        #expect(state["right"] as? Int == 2)
        #expect(state["active"] as? String == "right")
        #expect(state["layout"] as? String == "side-by-side")
        #expect(await ask(.compareOpen, server).error == "the window compares already; `compare set` changes it and `compare exit` ends it")

        let time = window.engine.time
        let exited = await ask(.compareExit, server)
        #expect(exited.output == "Compare is closed: v2 on screen in w1\n")
        #expect(!window.isComparing)
        #expect(!window.engine.player.isMuted)
        #expect(window.companion == nil)
        #expect(window.versionNumber == 2)
        #expect(abs(window.engine.time - time) < 0.05)
        #expect(try await compare(server) == nil)
        app.listeners.stop()
    }

    @Test("while comparing a new message goes to the side the person draws or clicks on, and the composer to the active side")
    func messagesGoToTheSide() async throws {
        defer { cleanUp() }
        let (app, window, server) = try await run()
        try await window.seek(to: 1)
        #expect(await ask(.compareStart, server).ok)

        // The right side, v2, takes the first message.
        let first = try await window.addMessage(text: "Logo too small", at: 1)
        #expect(first.thread.version?.number == 2)

        // A drag on the left side draws on v1.
        window.beginRegion(on: .left)
        #expect(window.activeSide == .left)
        #expect(window.versionNumber == 1)
        // The sound follows the active side.
        #expect(window.pair?.left.player.isMuted == false)
        #expect(window.pair?.right.player.isMuted == true)
        window.endRegion(try Region(x: 0.1, y: 0.1, w: 0.3, h: 0.3))
        window.draft?.text = "Crop the title"
        // A click on the right side: the words are queued on v1, where they were written.
        window.clickFrame(on: .right)
        #expect(window.activeSide == .right)
        let deadline = ContinuousClock.now + .seconds(10)
        while window.threads.count < 3, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        let onV1 = try #require(window.threads.first { $0.anchor?.path == Self.sample.path })
        #expect(onV1.messages.first?.text == "Crop the title")
        #expect(onV1.messages.first?.region != nil)
        // Each side's frame shows its own version's thread.
        #expect(window.frameMarks.map(\.number) == [first.thread.number])
        #expect(window.frameMarks(on: .left).map(\.number) == [onV1.number])

        // The composer writes to the active side.
        _ = try window.compose(text: "And the colour", region: nil, general: false)
        #expect(try await window.writeComposer() == .reply)
        #expect(window.threads.first { $0.number == first.thread.number }?.messages.count == 2)

        // A thread of the other side's version makes that side active, without leaving Compare.
        _ = try await window.showThread(onV1.id.text)
        #expect(window.isComparing)
        #expect(window.activeSide == .left)
        #expect(await ask(.state, server).output.contains("messages go to v1 on the left"))

        // compare set --side does what a click does.
        #expect(await ask(.compareSet(CompareChange(side: .right)), server).ok)
        #expect(window.activeSide == .right)
        app.listeners.stop()
    }

    @Test("Flip shows one side, the flip key shows the other and makes it active, and Slider moves its handle")
    func flipAndSlider() async throws {
        defer { cleanUp() }
        let (app, window, server) = try await run()
        #expect(await ask(.compareOpen, server).ok)
        #expect(await ask(.compareSet(CompareChange(layout: .flip)), server).ok)
        #expect(await ask(.compareStart, server).output
            == "compare: v1 on the left and v2 on the right, flip showing the left, messages go to v1 on the left\n")
        #expect(window.activeSide == .left)
        #expect(window.flipCompare())
        #expect(window.compare?.showing == .right)
        #expect(window.activeSide == .right)
        #expect(await ask(.compareSet(CompareChange(side: .left)), server).ok)
        #expect(window.compare?.showing == .left)

        // A swap keeps the picture: the version showing stays, on the other side.
        #expect(await ask(.compareSwap, server).output
            == "compare: v2 on the left and v1 on the right, flip showing the right, messages go to v1 on the right\n")
        #expect(window.versionNumber == 1)

        #expect(await ask(.compareSet(CompareChange(layout: .slider, slider: 0.3)), server).output
            == "compare: v2 on the left and v1 on the right, slider at 30%, messages go to v1 on the right\n")
        #expect(!window.flipCompare())
        window.slideCompare(to: 0.75)
        #expect(window.compare?.slider == 0.75)
        let state = try #require(try await compare(server))
        #expect(state["showing"] is NSNull)
        #expect(state["slider"] as? Double == 0.75)
        app.listeners.stop()
    }

    @Test("a side's new version loads at the playhead, the other side's swaps them, and Escape and another version end Compare")
    func changeSidesAndLeave() async throws {
        defer { cleanUp() }
        let (app, window, server) = try await run(more: 1)
        try await window.seek(to: 1)
        #expect(await ask(.compareStart, server).ok)
        #expect((window.compare?.number(.left), window.compare?.number(.right)) == (2, 3))

        // The left side, not active, takes v1.
        #expect(await ask(.compareSet(CompareChange(left: 1)), server).ok)
        #expect(window.companion?.url == Self.sample)
        #expect(abs((window.pair?.left.time ?? 0) - 1) < 0.05)
        // The right side, active, takes v2: the version on screen changes with it.
        #expect(await ask(.compareSet(CompareChange(right: 2)), server).ok)
        #expect(window.versionNumber == 2)
        #expect(window.video?.url == Self.launch)
        // A side's new player is heard only when its side is active.
        #expect(window.pair?.right.player.isMuted == false)
        #expect(window.pair?.left.player.isMuted == true)
        // v1 on the right swaps the sides; v2 stays active, now on the left.
        #expect(await ask(.compareSet(CompareChange(right: 1)), server).ok)
        #expect((window.compare?.number(.left), window.compare?.number(.right)) == (2, 1))
        #expect(window.activeSide == .left)
        #expect(window.versionNumber == 2)
        #expect(window.pair?.left.player.isMuted == false)
        #expect(window.pair?.right.player.isMuted == true)

        // version show of a side's version makes that side active.
        #expect(await ask(.versionShow(number: 1), server).ok)
        #expect(window.isComparing)
        #expect(window.activeSide == .right)
        #expect(await ask(.versionShow(number: 2), server).ok)
        #expect(window.activeSide == .left)

        // Escape ends Compare: the right side's version is on screen.
        #expect(window.escape())
        #expect(!window.isComparing)
        #expect(window.versionNumber == 1)

        // Another version ends a comparison and comes on screen.
        #expect(await ask(.compareStart, server).ok)
        #expect(await ask(.versionShow(number: 3), server).ok)
        #expect(!window.isComparing)
        #expect(window.versionNumber == 3)

        // Closing the window ends a comparison: the inactive side's player lets its video go.
        #expect(await ask(.compareStart, server).ok)
        let companion = try #require(window.pair?.engine(window.activeSide?.other ?? .left))
        app.windowClosed(window)
        #expect(!window.isComparing)
        #expect(companion.player.currentItem == nil)
        app.listeners.stop()
    }

    @Test("Compare is refused on a plain video and on a project of one version")
    func refused() async throws {
        defer { cleanUp() }
        let app = AppModel(environment: [SupportFolder.overrideVariable: support.path], speech: SlowRecognizer())
        let window = app.makeWindow()
        try await window.open(Self.sample)
        let server = ControlServer(
            socket: URL(fileURLWithPath: "/nowhere/control.sock"), app: app, listeners: { app.listeners },
            screenshotter: ControlServerTests.FakeScreenshotter(), quit: {}
        )
        #expect(await ask(.controlTake(waitSeconds: nil), server).ok)
        #expect(!window.canCompare)
        let plain = "this window holds a plain video, which has no versions to compare; `project new` makes it a project"
        #expect(await ask(.compareOpen, server).error == plain)
        #expect(await ask(.compareStart, server).error == plain)
        #expect(await ask(.comparePick(side: .left), server).error == plain)
        #expect(window.state().project == nil)

        #expect(await ask(.projectNew(slug: "launch-video", path: Self.sample.path), server).ok)
        #expect(!window.canCompare)
        #expect(await ask(.compareOpen, server).error == "the project has 1 version; Compare needs two, and `project add` adds the next")
        app.listeners.stop()
    }
}
