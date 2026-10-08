import Foundation
@testable import ReviewApp
import ReviewConfig
import ReviewCore
import ReviewLease
import ReviewStore
import ReviewTranscript
import ReviewWire
import Testing

/// What a restart keeps: one run of the app's model on a support folder,
/// then a new model on the same folder, as the app is after `app quit` and
/// `app open`. No window and no socket.
@Suite("Threads and messages across restarts", .serialized)
struct PersistenceTests {
    nonisolated static let operatorAgent = Holder(key: "operator", name: "Claude Code", place: "/work")
    nonisolated static let listener = Holder(key: "listener-1", name: "Mate", place: "/shop")
    nonisolated static let restarted = Holder(key: "listener-2", name: "Mate", place: "/shop")

    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("havooch-tests-\(UUID().uuidString)", isDirectory: true)
    var support: URL { root.appendingPathComponent("support", isDirectory: true) }

    private func cleanUp() {
        try? FileManager.default.removeItem(at: root)
    }

    /// One run of the app on `support`: its model and the server in front
    /// of it. With `reopening`, the person opens the last video again; a
    /// launch opens none by itself.
    private func run(
        on support: URL? = nil, reopening: Bool = false, speech: any SpeechRecognizing = SlowRecognizer()
    ) async -> (WindowModel, ControlServer) {
        let model = AppModel(environment: [SupportFolder.overrideVariable: (support ?? self.support).path], speech: speech).makeWindow()
        if reopening, let last = model.recents.first { try? await model.open(last.url) }
        let server = ControlServer(
            socket: URL(fileURLWithPath: "/nowhere/control.sock"), app: model.app, listeners: { model.app.listeners },
            screenshotter: ControlServerTests.FakeScreenshotter(), quit: {}
        )
        return (model, server)
    }

    /// A copy of the fixture video named `name` in `folder` under the
    /// test's root, with the sidecars named.
    private func copy(to folder: String, as name: String = "sample.mp4", sidecars: [String] = []) throws -> URL {
        let target = root.appendingPathComponent(folder, isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let fixtures = MessageTests.fixture.deletingLastPathComponent()
        try FileManager.default.copyItem(at: MessageTests.fixture, to: target.appendingPathComponent(name))
        for sidecar in sidecars {
            try FileManager.default.copyItem(at: fixtures.appendingPathComponent(sidecar), to: target.appendingPathComponent(sidecar))
        }
        return target.appendingPathComponent(name)
    }

    private func object(_ text: String) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    }

    private func state(_ model: WindowModel) throws -> [String: Any] {
        try object(model.state().json)
    }

    private func listen(_ request: ControlRequest, _ server: ControlServer, as holder: Holder = listener) async -> ControlReply {
        await server.replyWritten(to: request.sent(by: holder, json: true)).reply
    }

    private func eventually(_ condition: () -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(10)
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    /// A review as the acceptance scenario builds it: a send of two
    /// messages on #1 and #2 (one on a region) that the listener took,
    /// acknowledged, asked about and finished in part, a queued message on
    /// #3, a popover frame on #2 and a note. Returns the ids of the send,
    /// its two messages and their threads.
    private func build(
        _ model: WindowModel, _ server: ControlServer
    ) async throws -> (send: String, first: String, second: String, one: String, two: String) {
        let first = try await model.addMessage(text: "Too fast here", at: 10)
        let second = try await model.addMessage(text: "This box", at: 12.5, region: try Region(x: 0.25, y: 0.2, w: 0.3, h: 0.25))
        try model.setContextNote("Look at the pricing page")
        let send = try await model.sendQueue()
        let two = second.thread.id
        #expect(await listen(.wait(timeoutSeconds: 0), server).ok)
        #expect(await listen(.ack(sendID: send.id, text: "On it"), server).ok)
        #expect(await listen(.ask(thread: two, question: "Which box?", waitSeconds: 0), server).timedOut == true)
        _ = try model.answer(two, text: "The left one")
        #expect(await listen(.reply(thread: two, text: "Fixed in abc123"), server).ok)
        #expect(await listen(.status(messageID: second.message.id, state: .done), server).ok)
        #expect(await listen(.status(messageID: first.message.id, state: .working), server).ok)
        #expect(await listen(.reply(thread: "0", text: "One left"), server).ok)
        try model.movePopover(try #require(ItemID(two)), to: PopoverFrame(x: 0.55, y: 0.1, w: 0.4, h: 0.35))
        _ = try await model.addMessage(text: "Still queued", at: 3)
        return (send.id, first.message.id, second.message.id, first.thread.id, two)
    }

    /// The person's messages' states, in the threads' order.
    private func states(_ model: WindowModel) -> [MessageState?] {
        model.threads.flatMap { $0.messages.filter(\.isWork).map(\.state) }
    }

    // MARK: - A restart

    @Test("after a restart the last video opened again is paused at its start, with the same threads, messages, states, sends, popover frames and note")
    func restart() async throws {
        defer { cleanUp() }
        let (model, server) = await run()
        try await model.open(MessageTests.fixture)
        _ = try await build(model, server)
        let before = try state(model)
        model.listeners().stop()

        let (again, _) = await run(reopening: true)

        let after = try state(again)
        for key in ["threads", "queue", "sends", "video", "popover"] {
            #expect(after[key] as? NSObject == before[key] as? NSObject, "\(key)")
        }
        #expect(again.threads.map(\.number) == [0, 3, 1, 2])
        #expect(states(again) == [.queued, .working, .done])
        #expect(again.threads[3].messages.map(\.kind) == [.message, .question, .answer, .message])
        #expect(again.threads[3].popoverFrame == PopoverFrame(x: 0.55, y: 0.1, w: 0.4, h: 0.35))
        #expect(again.threads[0].messages.map(\.text) == ["On it", "One left"])
        #expect(again.contextNote == "Look at the pricing page")
        #expect(again.engine.time == 0)
        #expect(!again.engine.isPlaying)
        #expect(again.problem == nil)
        // The agent keeps its name; nobody listens yet.
        #expect(again.agentName == "Mate")
        #expect(again.listeners().report(at: Date()) == StateReport.Listener(
            presence: "absent", waitOpen: false, session: "Mate", pendingSends: 0, takenSends: 1
        ))
        // Every picture the state names is still there.
        for thread in again.state().threads {
            if let keyframe = thread.keyframePath { #expect(FileManager.default.fileExists(atPath: keyframe)) }
            for message in thread.messages {
                if let crop = message.cropPath { #expect(FileManager.default.fileExists(atPath: crop)) }
            }
        }
        // The counters come back too: the next thread is #4.
        #expect(try await again.addMessage(text: "After the restart", at: 15).thread.number == 4)
    }

    @Test("a relaunch on demo data shows home with the last video first in recents, and opening it again brings back its threads and sends")
    func relaunchShowsHome() async throws {
        defer { cleanUp() }
        let video = try copy(to: "fixture", sidecars: ["sample.context.md"])
        let demo = [SupportFolder.overrideVariable: support.path, SupportFolder.demoRunVariable: "1"]
        let model = AppModel(environment: demo, speech: SlowRecognizer()).makeWindow()
        let server = ControlServer(
            socket: URL(fileURLWithPath: "/nowhere/control.sock"), app: model.app, listeners: { model.app.listeners },
            screenshotter: ControlServerTests.FakeScreenshotter(), quit: {}
        )
        try await model.open(video)
        _ = try await build(model, server)
        let before = try state(model)
        model.listeners().stop()

        // The launch opens no video by itself (spec 0.3.0): one window on home.
        let app = AppModel(environment: demo, speech: SlowRecognizer())
        let again = app.makeWindow()
        #expect(app.isDemoRun)
        #expect(again.video == nil)
        #expect(again.screen == .home)
        #expect(app.windows.windows.count == 1)
        #expect(again.recents.first?.url == video.standardizedFileURL)

        // The acceptance scenario's `player open` of the same file.
        try await again.open(video)
        let after = try state(again)
        for key in ["threads", "queue", "sends", "video"] {
            #expect(after[key] as? NSObject == before[key] as? NSObject, "\(key)")
        }
    }

    @Test("an agent reply on a thread the person isn't viewing is unread until its view opens, one on the thread shown is read, and both last a restart")
    func unread() async throws {
        defer { cleanUp() }
        let (model, server) = await run()
        try await model.open(MessageTests.fixture)
        let one = try await model.addMessage(text: "Too fast here", at: 10).thread.id
        _ = try await model.sendQueue()
        #expect(await listen(.wait(timeoutSeconds: 0), server).ok)
        func unread(_ model: WindowModel) -> [Bool] { model.state().threads.map(\.unread) }
        #expect(unread(model) == [false, false])

        #expect(await listen(.reply(thread: one, text: "Slowed it down"), server).ok)
        #expect(unread(model) == [false, true])
        #expect(try state(model)["threads"].flatMap { $0 as? [[String: Any]] }?.map { $0["unread"] as? Bool } == [false, true])
        #expect(model.state().lines.contains("\(one) sent unread\n"))

        _ = try await model.showThread("1")
        #expect(unread(model) == [false, false])
        // A reply on the thread the sidebar shows is read as it comes; one on another isn't.
        #expect(await listen(.reply(thread: one, text: "And the title"), server).ok)
        #expect(await listen(.reply(thread: "0", text: "One left"), server).ok)
        #expect(unread(model) == [true, false])
        model.listeners().stop()

        let (again, _) = await run(reopening: true)
        #expect(unread(again) == [true, false])
        _ = try await again.showThread("0")
        #expect(unread(again) == [false, false])
    }

    /// What a run wrote in the support folder, but the settings file and
    /// its verdict: with `HAVOOCH_SUPPORT_DIR` set, `config.toml` is made
    /// in its `config/` on launch (ADR 0002).
    private func dataFiles(in folder: URL? = nil) throws -> [String] {
        let folder = folder ?? support
        guard FileManager.default.fileExists(atPath: folder.path) else { return [] }
        return try FileManager.default.subpathsOfDirectory(atPath: folder.path)
            .filter { $0 != ConfigVerdict.fileName && $0 != "config" && !$0.hasPrefix("config/") }
            .sorted()
    }

    @Test("a launch opens nothing, says nothing and writes nothing but its settings file, with or without a last video")
    func launchOpensNothing() async throws {
        defer { cleanUp() }
        let (empty, _) = await run()
        #expect(empty.video == nil)
        #expect(try dataFiles() == [])

        let video = try copy(to: "videos")
        try await empty.open(video)
        // A video with no message yet has no review file. Opening it
        // makes the first run done, in the settings file.
        #expect(try dataFiles() == ["recents.json", "settings.json"])

        let (again, _) = await run()
        #expect(again.video == nil)
        #expect(again.problem == nil)
        #expect(try dataFiles() == ["recents.json", "settings.json"])
    }

    // MARK: - Recent videos

    /// A second video, with content of its own.
    static let showcase = MessageTests.fixture.deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("showcase/halcyon-teaser.mp4")

    @Test("opening a video puts it first on the recent videos, opening another keeps where the first was left, and state reports each one")
    func recentVideos() async throws {
        defer { cleanUp() }
        let first = try copy(to: "first", as: "sample take.mp4")
        let (model, _) = await run()
        #expect(model.recents.isEmpty)
        let before = Date()
        try await model.open(first)
        await model.engine.seek(to: 4)
        try await model.open(Self.showcase)

        #expect(model.recents.map(\.path) == [Self.showcase.path, first.path])
        #expect(model.recents.map(\.title) == ["halcyon-teaser", "sample take"])
        #expect(model.recents.map(\.position) == [0, 4])
        #expect(model.recents.map(\.available) == [true, true])
        #expect(model.recents.allSatisfy { $0.openedAt >= before.addingTimeInterval(-1) && $0.openedAt <= Date() })

        let recents = try #require(try state(model)["recents"] as? [[String: Any]])
        #expect(recents.count == 2)
        #expect(Set(recents[1].keys) == ["path", "title", "contentHash", "openedAt", "position", "available"])
        #expect(recents[1]["path"] as? String == first.path)
        #expect(recents[1]["title"] as? String == "sample take")
        #expect(recents[1]["position"] as? Double == 4)
        #expect(recents[1]["available"] as? Bool == true)
        #expect((recents[1]["openedAt"] as? String).flatMap { try? Date($0, strategy: .iso8601) } != nil)
        #expect(model.state().lines.contains("recents: 2\n  halcyon-teaser at 0:00"))

        // A new run reads the same list.
        let (again, _) = await run()
        #expect(again.recents.map(\.path) == [Self.showcase.path, first.path])
        #expect(again.recents.map(\.position) == [0, 4])
    }

    @Test("savePosition keeps where the open video is on its recent entry; with no video it does nothing")
    func recentPosition() async throws {
        defer { cleanUp() }
        let (model, _) = await run()
        model.savePosition()
        #expect(try dataFiles() == [])

        try await model.open(MessageTests.fixture)
        await model.engine.seek(to: 2.5)
        model.savePosition()
        #expect(model.recents.map(\.position) == [2.5])
        let (again, _) = await run()
        #expect(again.recents.map(\.position) == [2.5])
        // Opening it again keeps the position and doesn't add a second entry.
        try await again.open(MessageTests.fixture)
        #expect(again.recents.map(\.position) == [2.5])
    }

    @Test("a moved video is reported unavailable; removing a recent video takes it off the list and the state, and keeps its review")
    func recentRemoval() async throws {
        defer { cleanUp() }
        let first = try copy(to: "first")
        let (model, _) = await run()
        try await model.open(first)
        _ = try await model.addMessage(text: "Too fast here", at: 1)
        let hash = try #require(model.video?.contentHash)
        try await model.open(Self.showcase)
        try FileManager.default.removeItem(at: first)

        #expect(model.recents.map(\.available) == [true, false])
        model.removeRecent(hash)
        #expect(model.recents.map(\.path) == [Self.showcase.path])
        #expect((try state(model)["recents"] as? [[String: Any]])?.count == 1)
        let (again, _) = await run()
        #expect(again.recents.map(\.path) == [Self.showcase.path])
        #expect(try Library(layout: SupportLayout(root: support)).load(.video(contentHash: hash))?.threads.count == 2)
    }

    @Test("each data folder keeps its own recent videos: a demo's video never joins the person's list")
    func recentVideosPerFolder() async throws {
        defer { cleanUp() }
        let demo = root.appendingPathComponent("demo", isDirectory: true)
        let (demoRun, _) = await run(on: demo)
        try await demoRun.open(MessageTests.fixture)
        let (real, _) = await run()
        try await real.open(Self.showcase)

        #expect(real.recents.map(\.path) == [Self.showcase.path])
        #expect(demoRun.recents.map(\.path) == [MessageTests.fixture.path])
        let (demoAgain, _) = await run(on: demo)
        #expect(demoAgain.recents.map(\.path) == [MessageTests.fixture.path])
    }

    // MARK: - The same video elsewhere

    @Test("a renamed copy of the video in another folder shows the same history, and the review records where it is now")
    func renamedCopy() async throws {
        defer { cleanUp() }
        let original = try copy(to: "first", sidecars: ["sample.context.md"])
        let (model, server) = await run()
        try await model.open(original)
        let ids = try await build(model, server)
        let before = try state(model)
        model.listeners().stop()

        let renamed = try copy(to: "second/deeper", as: "renamed take 2.mov")
        let (again, later) = await run()
        try await again.open(renamed)

        let after = try state(again)
        for key in ["threads", "queue", "sends"] {
            #expect(after[key] as? NSObject == before[key] as? NSObject, "\(key)")
        }
        let video = try #require(after["video"] as? [String: Any])
        #expect(video["path"] as? String == renamed.path)
        #expect(video["title"] as? String == "renamed take 2.mov")
        #expect(video["contextNote"] as? String == "Look at the pricing page")
        #expect(video["contentHash"] as? String == (before["video"] as? [String: Any])?["contentHash"] as? String)
        // One folder for the one content, and its review names the new path.
        #expect(try FileManager.default.contentsOfDirectory(atPath: support.appendingPathComponent("videos").path).count == 1)
        let hash = try #require(again.video?.contentHash)
        let kept = try #require(try Library(layout: SupportLayout(root: support)).load(.video(contentHash: hash)))
        #expect(kept.video.path == renamed.path)
        #expect(kept.video.title == "renamed take 2.mov")

        // The history goes on under the new name.
        #expect(await listen(.status(messageID: ids.first, state: .done), later).ok)
        #expect(states(again) == [.queued, .done, .done])
    }

    @Test("what the listener says on a thread while its video is opening is kept, in the player and on disk")
    func changedWhileOpening() async throws {
        defer { cleanUp() }
        let (model, server) = await run()
        try await model.open(MessageTests.fixture)
        let ids = try await build(model, server)
        model.listeners().stop()

        let (again, later) = await run()
        let opening = Task { try await again.open(MessageTests.fixture) }
        // The player has the file and isn't ready yet: the video is on its way in.
        let deadline = ContinuousClock.now + .seconds(10)
        while again.engine.player.currentItem == nil, ContinuousClock.now < deadline { await Task.yield() }
        #expect(await listen(.status(messageID: ids.first, state: .done), later).ok)
        #expect(await listen(.reply(thread: ids.one, text: "Slowed it down"), later).ok)
        #expect(again.video == nil, "the listener spoke after the video was open: the test missed the opening")
        try await opening.value

        #expect(states(again) == [.queued, .done, .done])
        #expect(again.threads[2].messages.map(\.text) == ["Too fast here", "Slowed it down"])
        let hash = try #require(again.video?.contentHash)
        let kept = try #require(try Library(layout: SupportLayout(root: support)).load(.video(contentHash: hash)))
        #expect(kept.threads.flatMap { $0.messages.filter(\.isWork).map(\.state) } == [.queued, .done, .done])
        #expect(kept.threads.first { $0.id.text == ids.one }?.messages.map(\.text) == ["Too fast here", "Slowed it down"])
    }

    @Test("demo data and real data don't mix: the same video on another support folder has no history, and each folder keeps its own")
    func separateSupportFolders() async throws {
        defer { cleanUp() }
        let demo = root.appendingPathComponent("demo", isDirectory: true)
        let (model, server) = await run(on: demo)
        try await model.open(MessageTests.fixture)
        let ids = try await build(model, server)
        model.listeners().stop()

        let (real, realServer) = await run(reopening: true)
        #expect(real.video == nil)
        try await real.open(MessageTests.fixture)
        #expect(real.threads.map(\.number) == [0])
        #expect(real.sends.isEmpty)
        #expect(real.contextNote == "")
        #expect(real.listeners().outbox == Outbox())
        #expect(await listen(.status(messageID: ids.first, state: .done), realServer).error.contains("no message"))
        #expect(await listen(.wait(timeoutSeconds: 0), realServer).timedOut == true)
        // The real folder holds nothing of the demo's: its own wait kept that an agent connected.
        #expect(try dataFiles() == ["outboxes", "outboxes/\(try #require(real.reviewKey).fileName).json", "recents.json", "settings.json"])

        let (again, _) = await run(on: demo, reopening: true)
        #expect(states(again).count == 3)
    }

    // MARK: - The listener after a restart

    @Test("a send made with no listener before the quit is returned by a wait after the restart, with its keyframe, crop, transcript and context, with no video open")
    func pendingSend() async throws {
        defer { cleanUp() }
        let video = try copy(to: "videos", sidecars: ["voiceover.json", "sample.context.md"])
        let (model, _) = await run()
        try await model.open(video)
        let first = try await model.addMessage(text: "Too fast here", at: 10)
        let second = try await model.addMessage(text: "This box", at: 12.5, region: try Region(x: 0.25, y: 0.2, w: 0.3, h: 0.25))
        try model.setContextNote("Look at the pricing page")
        let send = try await model.sendQueue()
        let key = try #require(model.reviewKey)
        model.listeners().stop()

        // The next run opens no video: the listener names it.
        let (again, server) = await run()
        #expect(again.app.listeners.queue(for: key).outbox.pending.map(\.sendID.text) == [send.id])
        let reply = await listen(.wait(timeoutSeconds: 0, video: video.path), server)

        #expect(reply.ok)
        let payload = try object(reply.output)
        #expect((payload["send"] as? [String: Any])?["id"] as? String == send.id)
        let about = try #require(payload["video"] as? [String: Any])
        #expect(about["path"] as? String == video.path)
        #expect(about["title"] as? String == "sample.mp4")
        #expect(about["duration"] as? Double == 21.233)
        let context = try #require(payload["context"] as? String)
        let sidecar = try String(contentsOf: video.deletingLastPathComponent().appendingPathComponent("sample.context.md"), encoding: .utf8)
        #expect(context.hasPrefix(sidecar.trimmingCharacters(in: .whitespacesAndNewlines)))
        #expect(context.hasSuffix("## Note from the reviewer\n\nLook at the pricing page"))
        let threads = try #require(payload["threads"] as? [[String: Any]])
        let comments = threads.flatMap { ($0["messages"] as? [[String: Any]]) ?? [] }
        #expect(comments.map { $0["id"] as? String } == [first.message.id, second.message.id])
        for thread in threads {
            let keyframe = try #require(thread["keyframePath"] as? String)
            #expect(FileManager.default.fileExists(atPath: keyframe))
            // The voiceover's scene times, as the send cut them.
            let lines = try #require(thread["transcript"] as? [[String: AnyHashable]])
            #expect(lines == [TranscriptDeliveryTests.pause, TranscriptDeliveryTests.send, TranscriptDeliveryTests.answer])
        }
        #expect(comments[0]["cropPath"] is NSNull)
        let crop = try #require(comments[1]["cropPath"] as? String)
        #expect(FileManager.default.fileExists(atPath: crop))
        #expect(again.app.listeners.queue(for: key).outbox.taken.map(\.sendID.text) == [send.id])

        // The listener answers it, still with no video open, and that's kept too.
        #expect(await listen(.ack(sendID: send.id, text: nil), server).ok)
        #expect(await listen(.status(messageID: first.message.id, state: .done), server).ok)
        #expect(await listen(.reply(thread: second.thread.id, text: "Looking"), server).ok)
        again.app.listeners.stop()
        let (third, _) = await run(reopening: true)
        #expect(states(third) == [.done, .acknowledged])
        #expect(third.threads[2].messages.map(\.text) == ["This box", "Looking"])
    }

    @Test("a video with no sidecar: the speech lines a send kept are in it when a later run delivers it, with no transcription")
    func keptSpeech() async throws {
        defer { cleanUp() }
        let video = try copy(to: "videos")
        let speech = SlowRecognizer()
        let (model, _) = await run(speech: speech)
        try await model.open(video)
        speech.say(TranscriptLine(start: 0.2, end: 5.1, text: "This is Havooch."))
        speech.finish()
        await eventually { model.transcript?.complete == true }
        _ = try await model.addMessage(text: "Too fast here", at: 3)
        _ = try await model.sendQueue()
        model.listeners().stop()

        let later = SlowRecognizer()
        let (_, server) = await run(speech: later)
        let payload = try object(await listen(.wait(timeoutSeconds: 0, video: video.path), server).output)
        let threads = try #require(payload["threads"] as? [[String: Any]])
        #expect(threads.first?["transcript"] as? [[String: AnyHashable]] == [["start": 0.2, "end": 5.1, "text": "This is Havooch."]])
        #expect(later.runs == 0)
    }

    @Test("a taken, unfinished send stays with the same listener after a restart, and comes back to a new listener session with what's left of it")
    func takenSend() async throws {
        defer { cleanUp() }
        let (model, server) = await run()
        try await model.open(MessageTests.fixture)
        let ids = try await build(model, server)
        let key = try #require(model.reviewKey)
        let video = MessageTests.fixture.path
        model.listeners().stop()

        // The same listener: it has the send, and gets nothing twice.
        let (same, sameServer) = await run()
        #expect(same.app.listeners.queue(for: key).outbox.taken.map(\.sendID.text) == [ids.send])
        #expect(await listen(.wait(timeoutSeconds: 0, video: video), sameServer).timedOut == true)
        #expect(same.app.listeners.queue(for: key).outbox.taken.map(\.sendID.text) == [ids.send])
        same.app.listeners.stop()

        // A new listener session: the send is first in line again.
        let (again, againServer) = await run()
        let reply = await listen(.wait(timeoutSeconds: 0, video: video), againServer, as: Self.restarted)
        #expect(reply.ok)
        let payload = try object(reply.output)
        #expect((payload["send"] as? [String: Any])?["id"] as? String == ids.send)
        // Only the message that wasn't finished, and the context again.
        let threads = try #require(payload["threads"] as? [[String: Any]])
        #expect(threads.flatMap { ($0["messages"] as? [[String: Any]]) ?? [] }.map { $0["id"] as? String } == [ids.first])
        #expect((payload["context"] as? String)?.contains("Look at the pricing page") == true)
        again.app.listeners.stop()

        // The message went back to sent, and that's on disk as well.
        let (last, _) = await run(reopening: true)
        #expect(states(last) == [.queued, .sent, .done])
        #expect(last.listeners().outbox.session?.key == "listener-2")
        #expect(last.listeners().outbox.taken.map(\.sendID.text) == [ids.send])
    }

    @Test("a send whose outbox file was lost is in line again at the next launch")
    func lostOutbox() async throws {
        defer { cleanUp() }
        let (model, _) = await run()
        try await model.open(MessageTests.fixture)
        _ = try await model.addMessage(text: "Too fast here", at: 10)
        let send = try await model.sendQueue()
        let key = try #require(model.reviewKey)
        model.listeners().stop()
        try FileManager.default.removeItem(at: support.appendingPathComponent("outboxes"))

        let (again, server) = await run()
        #expect(again.app.listeners.queue(for: key).outbox.pending.map(\.sendID.text) == [send.id])
        #expect(await listen(.wait(timeoutSeconds: 0, video: MessageTests.fixture.path), server).ok)
    }

    // MARK: - Files that go wrong

    @Test("a review that doesn't read keeps its video shut: the open video stays, the reason is given, and the file is left as it is")
    func unreadableReview() async throws {
        defer { cleanUp() }
        let other = try copy(to: "videos")
        // Other content: the fixture with a byte more.
        var bytes = try Data(contentsOf: other)
        bytes.append(0)
        try bytes.write(to: other)
        let (model, _) = await run()
        try await model.open(other)
        let comment = try await model.addMessage(text: "Kept", at: 1).message
        let hash = try #require(model.video?.contentHash)
        model.listeners().stop()
        let file = Library(layout: SupportLayout(root: support)).layout.reviewFile(.video(contentHash: hash))
        let half = try Data(contentsOf: file).prefix(120)
        try half.write(to: file)

        let (again, later) = await run()
        do throws(AppRefusal) {
            try await again.open(other)
            Issue.record("a review that doesn't read opened")
        } catch {
            #expect(error.reason.contains("review.json doesn't read"))
        }
        #expect(again.video == nil)
        try await again.open(MessageTests.fixture)
        await #expect(throws: AppRefusal.self) { try await again.open(other) }
        #expect(again.video?.url == MessageTests.fixture.standardizedFileURL)
        #expect(await listen(.status(messageID: comment.id, state: .done), later).error.contains("no message"))
        #expect(try Data(contentsOf: file) == half)
    }

    @Test("a change that can't be saved is refused and changes nothing")
    func unsaved() async throws {
        defer { cleanUp() }
        let (model, server) = await run()
        try await model.open(MessageTests.fixture)
        let ids = try await build(model, server)
        let before = try state(model)
        let hash = try #require(model.video?.contentHash)
        let folder = Library(layout: SupportLayout(root: support)).layout.reviewFile(.video(contentHash: hash)).deletingLastPathComponent()
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path) }

        let refused = await listen(.status(messageID: ids.first, state: .done), server)
        #expect(!refused.ok)
        #expect(refused.error.hasPrefix("nothing changed: couldn't write "))
        #expect(throws: AppRefusal.self) { try model.setContextNote("Another note") }
        let after = try state(model)
        for key in ["threads", "sends", "video"] {
            #expect(after[key] as? NSObject == before[key] as? NSObject, "\(key)")
        }

        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path)
        #expect(await listen(.status(messageID: ids.first, state: .done), server).ok)
    }
}
