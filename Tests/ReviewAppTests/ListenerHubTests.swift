import Foundation
@testable import ReviewApp
import ReviewCore
import ReviewLease
import ReviewStore
import ReviewWire
import Testing

/// One listener per window (ADR 0003, F2, F3): each video's review has its
/// own `ListenerQueue` and outbox, `wait --video` binds to that video's
/// review and a bare `wait` to the key window's, the listener's other
/// commands find their review by the id prefix, and a new agent on a
/// review takes over from the one that was there. The app model and its
/// control server, with no scene and no socket; no video plays.
@Suite("A listener per window", .serialized)
struct ListenerHubTests {
    static let claude = Holder(key: "claude-1", name: "Claude Code", place: "/Users/me/shop")
    static let codex = Holder(key: "codex-1", name: "Codex", place: "/Users/me/site")

    let support = FileManager.default.temporaryDirectory
        .appendingPathComponent("havooch-tests-\(UUID().uuidString)", isDirectory: true)

    private func cleanUp() {
        try? FileManager.default.removeItem(at: support)
    }

    /// The app on a fresh folder with two windows, the sample in `w1` and
    /// the launch video in `w2` (key), each with one queued message, and
    /// the server in front of them.
    private func run() async throws -> (app: AppModel, sample: WindowModel, launch: WindowModel, server: ControlServer) {
        let app = AppModel(environment: [SupportFolder.overrideVariable: support.path], speech: SlowRecognizer())
        let sample = app.makeWindow()
        try await sample.open(MessageTests.fixture)
        let launch = app.makeWindow()
        try await launch.open(WindowTests.launch)
        app.windows.becameKey(launch)
        _ = try await sample.addMessage(text: "Too fast here", at: 2)
        _ = try await launch.addMessage(text: "Brighter logo", at: 1)
        let server = ControlServer(
            socket: URL(fileURLWithPath: "/nowhere/control.sock"), app: app, listeners: { app.listeners },
            screenshotter: ControlServerTests.FakeScreenshotter(), quit: {}
        )
        return (app, sample, launch, server)
    }

    /// A `wait` held open in the background, as `holder`'s.
    private func waiting(_ server: ControlServer, _ holder: Holder, video: URL?) -> Task<ControlServer.Answer, Never> {
        Task { await server.replyWritten(to: ControlRequest.wait(timeoutSeconds: 30, video: video?.path).sent(by: holder)) }
    }

    private func listen(_ request: ControlRequest, _ server: ControlServer, as holder: Holder) async -> ControlReply {
        await server.replyWritten(to: request.sent(by: holder)).reply
    }

    private func eventually(_ condition: () -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(10)
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    private func object(_ output: String) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any])
    }

    @Test("two agents wait on two videos: a send from one window reaches only its own listener, and each window shows its own")
    func sendReachesItsOwnListener() async throws {
        defer { cleanUp() }
        let (app, sample, launch, server) = try await run()
        let onSample = waiting(server, Self.claude, video: MessageTests.fixture)
        let onLaunch = waiting(server, Self.codex, video: WindowTests.launch)
        await eventually { sample.listeners().outbox.isWaitOpen && launch.listeners().outbox.isWaitOpen }
        #expect(sample.listener !== launch.listener)

        let send = try await sample.sendQueue()
        let answer = await onSample.value
        #expect(answer.delivered?.sendID.text == send.id)
        let payload = try object(answer.reply.output)
        #expect((payload["video"] as? [String: Any])?["path"] as? String == MessageTests.fixture.standardizedFileURL.path)

        // The other agent still waits, with nothing: the send was never its.
        #expect(launch.listeners().outbox.isWaitOpen)
        #expect(launch.listeners().outbox.pending.isEmpty)
        #expect(launch.listeners().outbox.session?.name == "Codex")
        #expect(sample.listeners().outbox.taken.map(\.sendID.text) == [send.id])

        // Each window's state and the window list name their own listener.
        let state = try object(await server.reply(to: ControlRequest.state.sent(by: Self.claude, json: true)).reply.output)
        let listed = try #require(state["windows"] as? [[String: Any]])
        #expect(listed.map { ($0["listener"] as? [String: Any])?["session"] as? String } == ["Claude Code", "Codex"])
        #expect((state["listener"] as? [String: Any])?["session"] as? String == "Codex")
        let windows = app.windowList()
        #expect(windows.map(\.listener?.session) == ["Claude Code", "Codex"])
        #expect(windows.map(\.listener?.presence) == ["working", "listening"])
        #expect(sample.state().listener.session == "Claude Code")
        #expect(launch.state().listener.session == "Codex")
        #expect(windows[0].line.hasSuffix("listener working (Claude Code)"))

        // The launch window's send goes to Codex.
        let second = try await launch.sendQueue()
        #expect(await onLaunch.value.delivered?.sendID.text == second.id)
        app.listeners.stop()
    }

    @Test("a wait with no --video binds to the key window's review, and is refused when the key window holds no video")
    func bareWaitBindsToTheKeyWindow() async throws {
        defer { cleanUp() }
        let (app, sample, launch, server) = try await run()
        let bare = waiting(server, Self.claude, video: nil)
        await eventually { launch.listeners().outbox.isWaitOpen }
        #expect(!sample.listeners().outbox.isWaitOpen)
        let send = try await launch.sendQueue()
        #expect(await bare.value.delivered?.sendID.text == send.id)

        let empty = app.makeWindow()
        app.windows.becameKey(empty)
        let refused = await listen(.wait(timeoutSeconds: 0), server, as: Self.claude)
        #expect(refused.error == "no window holds a video to listen to; name one with `havooch wait --video <path>`")
        let missing = await listen(.wait(timeoutSeconds: 0, video: "/nowhere/cut.mp4"), server, as: Self.claude)
        #expect(missing.error == "no video file at /nowhere/cut.mp4")
    }

    @Test("ack, status, reply and ask find their review by the id prefix, whichever window is key, and a bare number is the key window's")
    func answersFindTheirReview() async throws {
        defer { cleanUp() }
        let (app, sample, launch, server) = try await run()
        let send = try await sample.sendQueue()
        let taken = await listen(.wait(timeoutSeconds: 0, video: MessageTests.fixture.path), server, as: Self.claude)
        #expect(taken.ok)
        let thread = try #require(sample.threads.last)
        let message = try #require(thread.messages.first)

        // The launch window is key; the ids name the sample's review.
        #expect(app.windows.key === launch)
        #expect(await listen(.ack(sendID: send.id, text: "On it"), server, as: Self.claude).ok)
        #expect(await listen(.status(messageID: message.id.text, state: .working, text: "Slowing it"), server, as: Self.claude).ok)
        #expect(await listen(.reply(thread: thread.id.text, text: "Slower now"), server, as: Self.claude).ok)
        #expect(sample.listeners().activity(on: thread.id, at: Date())?.text == "Slowing it")
        #expect(launch.listeners().activities(at: Date()).isEmpty)
        #expect(sample.threads.last?.messages.map(\.text) == ["Too fast here", "Slower now"])
        // The notices go up in the window that holds the review, not the key one.
        #expect(sample.notices.map(\.kind) == [.acknowledgement, .message])
        #expect(launch.notices.isEmpty)

        // A bare number is a thread of the key window's video, which has none sent.
        let bare = await listen(.reply(thread: "1", text: "Hi"), server, as: Self.claude)
        #expect(!bare.ok)
        _ = try await launch.sendQueue()
        #expect(await listen(.reply(thread: "1", text: "Logo is brighter"), server, as: Self.codex).ok)
        #expect(launch.threads.last?.messages.map(\.text) == ["Brighter logo", "Logo is brighter"])
        #expect(launch.listeners().outbox.lastHeard != nil)
    }

    @Test("a new agent's wait on a review replaces the one that was there: its wait ends, and the window says who took over")
    func takeover() async throws {
        defer { cleanUp() }
        let (_, sample, launch, server) = try await run()
        let first = waiting(server, Self.claude, video: MessageTests.fixture)
        await eventually { sample.listeners().outbox.isWaitOpen }

        let second = waiting(server, Self.codex, video: MessageTests.fixture)
        let ended = await first.value.reply
        #expect(ended.error == "Codex took over listening to this video: one listener per video; stop listening and tell the person")
        let notice = try #require(sample.notices.last)
        #expect(notice.kind == .takeover)
        #expect(notice.text == "Codex took over from Claude Code")
        #expect(notice.title == "New listener")
        #expect(launch.notices.isEmpty)
        #expect(sample.state().listener.tookOverFrom == "Claude Code")
        #expect(sample.state().listener.session == "Codex")
        #expect(sample.state().lines.contains("listener: listening (Codex, took over from Claude Code)"))

        // Codex listens now: the window's send is its.
        let send = try await sample.sendQueue()
        #expect(await second.value.delivered?.sendID.text == send.id)
    }

    @Test("a new agent after one that went away is no takeover, and the same agent waiting again isn't either")
    func noTakeoverFromAnAbsentListener() async throws {
        defer { cleanUp() }
        let (_, sample, _, server) = try await run()
        // Claude Code listened once, then went away.
        #expect(await listen(.wait(timeoutSeconds: 0, video: MessageTests.fixture.path), server, as: Self.claude).timedOut == true)
        let gone = Date().addingTimeInterval(Outbox.listeningGrace + 1)
        #expect(sample.listeners().presence(at: gone) == .absent)

        // The same agent again: replaced, no notice.
        let first = waiting(server, Self.claude, video: MessageTests.fixture)
        await eventually { sample.listeners().outbox.isWaitOpen }
        let again = waiting(server, Self.claude, video: MessageTests.fixture)
        #expect(await first.value.reply.error == "a newer `havooch wait` took this one's place: one listener at a time")
        #expect(sample.notices.isEmpty)
        sample.app.listeners.stop()
        _ = await again.value
    }

    @Test("the outbox of builds before a listener per review is split on launch, so each video's listener gets its own sends")
    func formerOutboxMigrates() async throws {
        defer { cleanUp() }
        var hashes: [String] = []
        do {
            let (app, sample, launch, _) = try await run()
            _ = try await sample.sendQueue()
            _ = try await launch.sendQueue()
            hashes = [try #require(sample.video?.contentHash), try #require(launch.video?.contentHash)]
            app.listeners.stop()
        }
        // As a build before this one left the folder: one outbox for every video.
        let layout = SupportLayout(root: support)
        var former = Outbox()
        for hash in hashes {
            former.enqueue(contentsOf: Library(layout: layout).loadOutbox(.video(contentHash: hash)).pending)
        }
        #expect(former.pending.count == 2)
        try Library(layout: layout).save(former, of: .video(contentHash: "former"))
        try FileManager.default.moveItem(at: layout.outboxFile(.video(contentHash: "former")), to: layout.formerOutboxFile)
        try FileManager.default.removeItem(at: layout.outboxFile(.video(contentHash: hashes[0])))
        try FileManager.default.removeItem(at: layout.outboxFile(.video(contentHash: hashes[1])))

        let app = AppModel(environment: [SupportFolder.overrideVariable: support.path], speech: SlowRecognizer())
        #expect(!FileManager.default.fileExists(atPath: layout.formerOutboxFile.path))
        for hash in hashes {
            #expect(app.listeners.queue(ofVideo: hash).outbox.pending.map(\.contentHash) == [hash])
        }
    }
}

private extension Outbox {
    mutating func enqueue(contentsOf refs: [SendRef]) {
        for ref in refs { enqueue(ref) }
    }
}
