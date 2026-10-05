import Foundation
@testable import ReviewApp
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
        .appendingPathComponent("video-review-tests-\(UUID().uuidString)", isDirectory: true)
    var support: URL { root.appendingPathComponent("support", isDirectory: true) }

    private func cleanUp() {
        try? FileManager.default.removeItem(at: root)
    }

    /// One run of the app on `support`: its model and the server in front
    /// of it. With `reopening`, it opens the last video as a launch does.
    private func run(
        on support: URL? = nil, reopening: Bool = false, speech: any SpeechRecognizing = SlowRecognizer()
    ) async -> (AppModel, ControlServer) {
        let model = AppModel(environment: [SupportFolder.overrideVariable: (support ?? self.support).path], speech: speech)
        if reopening { await model.openRecent() }
        let server = ControlServer(
            socket: URL(fileURLWithPath: "/nowhere/control.sock"), app: model, listeners: model.listeners,
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

    private func state(_ model: AppModel) throws -> [String: Any] {
        try object(model.state().json)
    }

    private func listen(_ request: ControlRequest, _ server: ControlServer, as holder: Holder = listener) async -> ControlReply {
        await server.reply(to: request.sent(by: holder, json: true)).reply
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
        _ model: AppModel, _ server: ControlServer
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
    private func states(_ model: AppModel) -> [MessageState?] {
        model.threads.flatMap { $0.messages.filter(\.isWork).map(\.state) }
    }

    // MARK: - A restart

    @Test("after a restart the last video is open again, paused at its start, with the same threads, messages, states, sends, popover frames and note")
    func restart() async throws {
        defer { cleanUp() }
        let (model, server) = await run()
        try await model.open(MessageTests.fixture)
        _ = try await build(model, server)
        let before = try state(model)
        model.listeners.stop()

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
        #expect(again.listeners.report(at: Date()) == StateReport.Listener(
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

    @Test("a launch with no last video, or one whose file is gone, opens nothing, says nothing and writes nothing")
    func nothingToReopen() async throws {
        defer { cleanUp() }
        let (empty, _) = await run(reopening: true)
        #expect(empty.video == nil)
        #expect(!FileManager.default.fileExists(atPath: support.path))

        let video = try copy(to: "videos")
        try await empty.open(video)
        // A video with no message yet has no review file.
        #expect(try FileManager.default.contentsOfDirectory(atPath: support.path) == ["recent.json"])
        try FileManager.default.removeItem(at: video)

        let (again, _) = await run(reopening: true)
        #expect(again.video == nil)
        #expect(again.problem == nil)
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
        model.listeners.stop()

        let renamed = try copy(to: "second/deeper", as: "renamed take 2.mov")
        let (again, later) = await run()
        try await again.open(renamed)

        let after = try state(again)
        for key in ["threads", "queue", "sends"] {
            #expect(after[key] as? NSObject == before[key] as? NSObject, "\(key)")
        }
        let video = try #require(after["video"] as? [String: Any])
        #expect(video["path"] as? String == renamed.path)
        #expect(video["title"] as? String == "renamed take 2")
        #expect(video["contextNote"] as? String == "Look at the pricing page")
        #expect(video["contentHash"] as? String == (before["video"] as? [String: Any])?["contentHash"] as? String)
        // One folder for the one content, and its review names the new path.
        #expect(try FileManager.default.contentsOfDirectory(atPath: support.appendingPathComponent("videos").path).count == 1)
        let hash = try #require(again.video?.contentHash)
        let kept = try #require(try Library(layout: SupportLayout(root: support)).load(hash))
        #expect(kept.video.path == renamed.path)
        #expect(kept.video.title == "renamed take 2")

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
        model.listeners.stop()

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
        let kept = try #require(try Library(layout: SupportLayout(root: support)).load(hash))
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
        model.listeners.stop()

        let (real, realServer) = await run(reopening: true)
        #expect(real.video == nil)
        try await real.open(MessageTests.fixture)
        #expect(real.threads.map(\.number) == [0])
        #expect(real.sends.isEmpty)
        #expect(real.contextNote == "")
        #expect(real.listeners.outbox == Outbox())
        #expect(await listen(.status(messageID: ids.first, state: .done), realServer).error.contains("no message"))
        #expect(await listen(.wait(timeoutSeconds: 0), realServer).timedOut == true)
        // The real folder holds nothing of the demo's.
        let files = try FileManager.default.subpathsOfDirectory(atPath: support.path)
        #expect(files.sorted() == ["outbox.json", "recent.json"])

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
        model.listeners.stop()

        // The next run opens no video.
        let (again, server) = await run()
        #expect(again.listeners.outbox.pending.map(\.sendID.text) == [send.id])
        let reply = await listen(.wait(timeoutSeconds: 0), server)

        #expect(reply.ok)
        let payload = try object(reply.output)
        #expect((payload["send"] as? [String: Any])?["id"] as? String == send.id)
        let about = try #require(payload["video"] as? [String: Any])
        #expect(about["path"] as? String == video.path)
        #expect(about["title"] as? String == "sample")
        #expect(about["duration"] as? Double == 21.233)
        let context = try #require(payload["context"] as? String)
        let sidecar = try String(contentsOf: video.deletingLastPathComponent().appendingPathComponent("sample.context.md"), encoding: .utf8)
        #expect(context.hasPrefix(sidecar.trimmingCharacters(in: .whitespacesAndNewlines)))
        #expect(context.hasSuffix("## Note from the reviewer\n\nLook at the pricing page"))
        let comments = try #require(payload["messages"] as? [[String: Any]])
        #expect(comments.map { $0["id"] as? String } == [first.message.id, second.message.id])
        for comment in comments {
            let keyframe = try #require(comment["keyframePath"] as? String)
            #expect(FileManager.default.fileExists(atPath: keyframe))
            // The voiceover's scene times, at the frame rate kept with the review.
            let lines = try #require(comment["transcript"] as? [[String: AnyHashable]])
            #expect(lines == [TranscriptDeliveryTests.pause, TranscriptDeliveryTests.send, TranscriptDeliveryTests.answer])
        }
        #expect(comments[0]["cropPath"] is NSNull)
        let crop = try #require(comments[1]["cropPath"] as? String)
        #expect(FileManager.default.fileExists(atPath: crop))
        #expect(again.listeners.outbox.taken.map(\.sendID.text) == [send.id])

        // The listener answers it, still with no video open, and that's kept too.
        #expect(await listen(.ack(sendID: send.id, text: nil), server).ok)
        #expect(await listen(.status(messageID: first.message.id, state: .done), server).ok)
        #expect(await listen(.reply(thread: second.thread.id, text: "Looking"), server).ok)
        again.listeners.stop()
        let (third, _) = await run(reopening: true)
        #expect(states(third) == [.done, .acknowledged])
        #expect(third.threads[2].messages.map(\.text) == ["This box", "Looking"])
    }

    @Test("a video with no sidecar: the speech transcript an earlier run finished is in a send a later run delivers without opening the video")
    func keptSpeech() async throws {
        defer { cleanUp() }
        let video = try copy(to: "videos")
        let speech = SlowRecognizer()
        let (model, _) = await run(speech: speech)
        try await model.open(video)
        speech.say(TranscriptLine(start: 0.2, end: 5.1, text: "This is Video Review."))
        speech.finish()
        await eventually { model.transcript?.complete == true }
        _ = try await model.addMessage(text: "Too fast here", at: 3)
        _ = try await model.sendQueue()
        model.listeners.stop()

        let later = SlowRecognizer()
        let (_, server) = await run(speech: later)
        let payload = try object(await listen(.wait(timeoutSeconds: 0), server).output)
        let comments = try #require(payload["messages"] as? [[String: Any]])
        #expect(comments.first?["transcript"] as? [[String: AnyHashable]] == [["start": 0.2, "end": 5.1, "text": "This is Video Review."]])
        #expect(later.runs == 0)
    }

    @Test("a taken, unfinished send stays with the same listener after a restart, and comes back to a new listener session with what's left of it")
    func takenSend() async throws {
        defer { cleanUp() }
        let (model, server) = await run()
        try await model.open(MessageTests.fixture)
        let ids = try await build(model, server)
        model.listeners.stop()

        // The same listener: it has the send, and gets nothing twice.
        let (same, sameServer) = await run()
        #expect(same.listeners.outbox.taken.map(\.sendID.text) == [ids.send])
        #expect(await listen(.wait(timeoutSeconds: 0), sameServer).timedOut == true)
        #expect(same.listeners.outbox.taken.map(\.sendID.text) == [ids.send])
        same.listeners.stop()

        // A new listener session: the send is first in line again.
        let (again, againServer) = await run()
        let reply = await listen(.wait(timeoutSeconds: 0), againServer, as: Self.restarted)
        #expect(reply.ok)
        let payload = try object(reply.output)
        #expect((payload["send"] as? [String: Any])?["id"] as? String == ids.send)
        // Only the message that wasn't finished, and the context again.
        #expect((payload["messages"] as? [[String: Any]])?.map { $0["id"] as? String } == [ids.first])
        #expect((payload["context"] as? String)?.contains("Look at the pricing page") == true)
        again.listeners.stop()

        // The message went back to sent, and that's on disk as well.
        let (last, _) = await run(reopening: true)
        #expect(states(last) == [.queued, .sent, .done])
        #expect(last.listeners.outbox.session?.key == "listener-2")
        #expect(last.listeners.outbox.taken.map(\.sendID.text) == [ids.send])
    }

    @Test("a send whose outbox file was lost is in line again at the next launch")
    func lostOutbox() async throws {
        defer { cleanUp() }
        let (model, _) = await run()
        try await model.open(MessageTests.fixture)
        _ = try await model.addMessage(text: "Too fast here", at: 10)
        let send = try await model.sendQueue()
        model.listeners.stop()
        try FileManager.default.removeItem(at: support.appendingPathComponent("outbox.json"))

        let (again, server) = await run()
        #expect(again.listeners.outbox.pending.map(\.sendID.text) == [send.id])
        #expect(await listen(.wait(timeoutSeconds: 0), server).ok)
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
        model.listeners.stop()
        let file = Library(layout: SupportLayout(root: support)).layout.reviewFile(hash)
        let half = try Data(contentsOf: file).prefix(120)
        try half.write(to: file)

        let (again, later) = await run(reopening: true)
        #expect(again.video == nil)
        #expect(again.problem?.title == "The last video didn't open")
        #expect(again.problem?.reason.contains("review.json doesn't read") == true)
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
        let folder = Library(layout: SupportLayout(root: support)).layout.reviewFile(hash).deletingLastPathComponent()
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
