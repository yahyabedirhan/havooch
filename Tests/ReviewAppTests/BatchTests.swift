import Darwin
import Foundation
@testable import ReviewApp
import ReviewCore
import ReviewWire
import Testing

/// Batches from the person to the listener: the app's model on the fixture
/// video and the control server in front of it, asked as an operator and a
/// listener ask it. No window; the real socket for the last two tests only.
@Suite("Sending a batch to a listener", .serialized)
@MainActor
struct BatchDeliveryTests {
    nonisolated static let operatorAgent = Holder(key: "operator", name: "Claude Code", place: "/work")
    nonisolated static let listener = Holder(key: "listener-1", name: "Claude Code", place: "/shop")
    nonisolated static let restarted = Holder(key: "listener-2", name: "Claude Code", place: "/shop")

    let support = FileManager.default.temporaryDirectory
        .appendingPathComponent("video-review-tests-\(UUID().uuidString)", isDirectory: true)

    private func cleanUp() {
        try? FileManager.default.removeItem(at: support)
    }

    /// The model with the fixture open, and the server in front of it.
    private func app(socket: URL = URL(fileURLWithPath: "/nowhere/control.sock")) async throws -> (AppModel, ControlServer) {
        let model = AppModel(environment: [SupportFolder.overrideVariable: support.path])
        try await model.open(CommentTests.fixture)
        let server = ControlServer(
            socket: socket, app: model, listeners: model.listeners, screenshotter: ControlServerTests.FakeScreenshotter(), quit: {}
        )
        return (model, server)
    }

    private func object(_ text: String) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    }

    /// Waits until `condition` holds: a held request is answered in a task.
    private func eventually(_ condition: () -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(10)
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    /// A listener's `wait`, held by the server until it's answered.
    private func waiting(_ server: ControlServer, as holder: Holder = listener, timeout: Int? = nil) -> Task<ControlServer.Answer, Never> {
        Task { await server.reply(to: ControlRequest.wait(timeoutSeconds: timeout).sent(by: holder)) }
    }

    /// Two queued comments: one on the frame at 10 s, one on a region at 12.5 s.
    private func queueTwo(_ model: AppModel) async throws -> (StateReport.Comment, StateReport.Comment) {
        let first = try await model.addComment(text: "Too fast here", at: 10)
        let second = try await model.addComment(text: "This box", at: 12.5, region: try Region(x: 0.25, y: 0.2, w: 0.3, h: 0.25))
        return (first, second)
    }

    // MARK: - With a listener waiting

    @Test("batch send with a wait open: the wait answers with the batch as the spec's payload, and every image is on disk")
    func sendToAWaitingListener() async throws {
        defer { cleanUp() }
        let (model, server) = try await app()
        let wait = waiting(server)
        await eventually { model.listeners.outbox.isWaitOpen }
        #expect(model.listeners.presence(at: Date()) == .listening)
        let (first, second) = try await queueTwo(model)

        let sent = await server.reply(to: ControlRequest.batchSend.sent(by: Self.operatorAgent))
        let answer = await wait.value

        let batch = try #require(model.batches.first)
        #expect(sent.reply == .done("\(batch.id) sent with 2 comments, taken by the listener\n"))
        #expect(answer.reply.ok)
        #expect(answer.delivered == BatchRef(batchID: batch.id, contentHash: try #require(model.video?.contentHash)))

        let payload = try object(answer.reply.output)
        #expect(Set(payload.keys) == ["batch", "video", "context", "comments"])
        let batchPart = try #require(payload["batch"] as? [String: String])
        #expect(batchPart["id"] == batch.id.text)
        #expect(ItemID(batch.id.text)?.kind == .batch)
        #expect(ISO8601DateFormatter().date(from: try #require(batchPart["sentAt"])) != nil)
        #expect(payload["video"] as? [String: AnyHashable] == [
            "path": CommentTests.fixture.standardizedFileURL.path, "contentHash": try #require(model.video?.contentHash),
            "duration": 21.233, "title": "sample",
        ])
        #expect((model.video?.contentHash.count ?? 0) == 64)
        // The fixture's sidecar, on this session's first batch. The transcript window isn't built yet.
        #expect(payload["context"] as? String == ContextReader.sidecar(beside: CommentTests.fixture)?.text)
        #expect((payload["context"] as? String)?.hasPrefix("# Context: sample\n") == true)
        let comments = try #require(payload["comments"] as? [[String: Any]])
        #expect(comments.count == 2)
        #expect(comments[0] as? [String: AnyHashable] == [
            "id": first.id, "time": 10, "text": "Too fast here", "keyframePath": first.keyframePath,
            "region": NSNull(), "cropPath": NSNull(), "transcript": [] as [String],
        ])
        #expect(comments[1]["id"] as? String == second.id)
        #expect(comments[1]["time"] as? Double == 12.5)
        #expect(comments[1]["text"] as? String == "This box")
        #expect(comments[1]["region"] as? [String: Double] == ["x": 0.25, "y": 0.2, "w": 0.3, "h": 0.25])
        #expect(comments[1]["keyframePath"] as? String == second.keyframePath)
        #expect(comments[1]["cropPath"] as? String == second.cropPath)
        for path in [first.keyframePath, second.keyframePath, try #require(second.cropPath)] {
            #expect(path.hasPrefix(support.path + "/"))
            #expect(FileManager.default.fileExists(atPath: path))
        }

        // The listener has the batch: it works, and waits no longer.
        #expect(model.listeners.outbox.taken.map(\.batchID) == [batch.id])
        #expect(model.listeners.outbox.pending.isEmpty)
        #expect(model.listeners.presence(at: Date()) == .working)
    }

    @Test("sent comments are sent in the state report, name their batch, and leave the queue")
    func sentInState() async throws {
        defer { cleanUp() }
        let (model, server) = try await app()
        let (first, second) = try await queueTwo(model)
        _ = await server.reply(to: ControlRequest.batchSend.sent(by: Self.operatorAgent))

        let state = try object(await server.reply(to: ControlRequest.state.sent(by: Self.listener, json: true)).reply.output)
        let comments = try #require(state["comments"] as? [[String: Any]])
        let batch = try #require((state["batches"] as? [[String: Any]])?.first)
        #expect(comments.map { $0["state"] as? String } == ["sent", "sent"])
        #expect(comments.map { $0["batchId"] as? String } == [batch["id"] as? String, batch["id"] as? String])
        #expect(batch["commentIds"] as? [String] == [first.id, second.id])
        #expect(state["queue"] as? [String] == [])
        #expect(model.comments.map(\.state) == [.sent, .sent])
        #expect(!model.canSend)
        // A sent comment is a record.
        let edit = await server.reply(to: ControlRequest.commentEdit(id: first.id, text: "new").sent(by: Self.operatorAgent))
        #expect(edit.reply == .refused("\(first.id) is sent, and only a queued comment can change"))
    }

    // MARK: - With no listener

    @Test("a batch sent before any wait waits in line, and the next wait returns it at once")
    func sendBeforeAnyWait() async throws {
        defer { cleanUp() }
        let (model, server) = try await app()
        _ = try await queueTwo(model)

        let sent = await server.reply(to: ControlRequest.batchSend.sent(by: Self.operatorAgent))

        let batch = try #require(model.batches.first)
        #expect(sent.reply == .done("\(batch.id) sent with 2 comments, waiting for a listener\n"))
        #expect(model.listeners.outbox.pending.map(\.batchID) == [batch.id])
        #expect(model.listeners.presence(at: Date()) == .absent)
        var state = try object(await server.reply(to: ControlRequest.state.sent(by: Self.listener, json: true)).reply.output)
        #expect(state["listener"] as? [String: AnyHashable] == [
            "presence": "absent", "waitOpen": false, "session": NSNull(), "pendingBatches": 1, "takenBatches": 0,
        ])

        let answer = await server.reply(to: ControlRequest.wait(timeoutSeconds: 0).sent(by: Self.listener))

        let payload = try object(answer.reply.output)
        #expect((payload["batch"] as? [String: String])?["id"] == batch.id.text)
        #expect((payload["comments"] as? [[String: Any]])?.count == 2)
        state = try object(await server.reply(to: ControlRequest.state.sent(by: Self.listener, json: true)).reply.output)
        #expect(state["listener"] as? [String: AnyHashable] == [
            "presence": "working", "waitOpen": false, "session": "Claude Code", "pendingBatches": 0, "takenBatches": 1,
        ])
        #expect(await server.reply(to: ControlRequest.state.sent(by: Self.listener)).reply.output
            .contains("listener: working (Claude Code), 0 batches waiting, 1 taken\n"))
    }

    @Test("batches go out first in, first out, one per wait")
    func oneBatchPerWait() async throws {
        defer { cleanUp() }
        let (model, server) = try await app()
        _ = try await model.addComment(text: "First", at: 3)
        _ = try await model.sendBatch()
        _ = try await model.addComment(text: "Second", at: 5)
        _ = try await model.sendBatch()
        let ids = model.batches.map(\.id.text)

        var got: [String?] = []
        for _ in 0..<2 {
            let answer = await server.reply(to: ControlRequest.wait(timeoutSeconds: 0).sent(by: Self.listener))
            got.append((try object(answer.reply.output)["batch"] as? [String: String])?["id"])
        }
        #expect(got == ids)
        #expect(await server.reply(to: ControlRequest.wait(timeoutSeconds: 0).sent(by: Self.listener)).reply == .ranOut)
    }

    @Test("a send with nothing queued is refused, and no batch is made")
    func nothingQueued() async throws {
        defer { cleanUp() }
        let (model, server) = try await app()
        let sent = await server.reply(to: ControlRequest.batchSend.sent(by: Self.operatorAgent))
        #expect(!sent.reply.ok)
        #expect(sent.reply.error.hasPrefix("no comment is queued"))
        #expect(model.batches.isEmpty)
        #expect(model.listeners.outbox.pending.isEmpty)
    }

    // MARK: - The person's key

    @Test("Cmd+Return goes the same way as batch send, and takes the words in the comment box with it")
    func sendFromTheKey() async throws {
        defer { cleanUp() }
        let (model, _) = try await app()
        _ = try await model.addComment(text: "Queued", at: 3)
        try await model.seek(to: 8)
        model.startDraft()
        model.draft?.text = "Still in the box"
        #expect(model.sendCount == 2)

        // What the key and the Send button call.
        model.send()
        await eventually { !model.batches.isEmpty }

        #expect(model.draft == nil)
        #expect(model.comments.map(\.text) == ["Queued", "Still in the box"])
        #expect(model.comments.map(\.state) == [.sent, .sent])
        #expect(model.batches.count == 1)
        #expect(model.listeners.outbox.pending.count == 1)
        #expect(model.sendCount == 0)

        // With nothing to send the key does nothing: no batch, no problem shown.
        model.send()
        try await Task.sleep(for: .milliseconds(50))
        #expect(model.batches.count == 1)
        #expect(model.problem == nil)
    }

    @Test("a comment whose keyframe is still being written when Cmd+Return is pressed joins the batch")
    func sendRightAfterReturn() async throws {
        defer { cleanUp() }
        let (model, _) = try await app()
        try await model.seek(to: 8)
        model.startDraft()
        model.draft?.text = "Just committed"
        model.commitDraft()
        #expect(model.comments.isEmpty)
        #expect(model.canSend)

        model.send()
        await eventually { !model.batches.isEmpty }

        #expect(model.comments.map(\.state) == [.sent])
        #expect(model.batches.first?.commentIDs == model.comments.map(\.id))
    }

    // MARK: - A wait that ends with no batch

    @Test("a wait whose timeout runs out answers that it ran out, and the listener is absent 5 s later")
    func timeout() async throws {
        defer { cleanUp() }
        let (model, server) = try await app()
        let started = Date()
        let wait = waiting(server, timeout: 1)
        await eventually { model.listeners.outbox.isWaitOpen }
        #expect(model.listeners.presence(at: Date()) == .listening)

        let answer = await wait.value

        #expect(answer.reply == .ranOut)
        #expect(answer.delivered == nil)
        #expect(Date().timeIntervalSince(started) >= 1)
        #expect(!model.listeners.outbox.isWaitOpen)
        let closed = try #require(model.listeners.outbox.lastHeard)
        #expect(model.listeners.presence(at: closed.addingTimeInterval(4)) == .listening)
        #expect(model.listeners.presence(at: closed.addingTimeInterval(5)) == .absent)
    }

    @Test("a newer wait replaces the one that's open: one listener at a time")
    func replaced() async throws {
        defer { cleanUp() }
        let (model, server) = try await app()
        let older = waiting(server)
        await eventually { model.listeners.outbox.isWaitOpen }
        let newer = waiting(server)

        #expect(await older.value.reply == .refused("a newer `video-review wait` took this one's place: one listener at a time"))
        #expect(model.listeners.outbox.isWaitOpen)
        _ = try await model.addComment(text: "For the newer one", at: 3)
        _ = try await model.sendBatch()
        #expect(await newer.value.reply.ok)
    }

    @Test("when the app quits, an open wait ends with no reply, so its command connects again")
    func quitting() async throws {
        defer { cleanUp() }
        let (model, server) = try await app()
        let wait = waiting(server)
        await eventually { model.listeners.outbox.isWaitOpen }
        server.stop()
        let answer = await wait.value
        #expect(answer.silent)
        #expect(answer.delivered == nil)
    }

    // MARK: - A batch that goes back

    @Test("a wait from a new listener session gets the batch the last one took and didn't finish; the same session doesn't")
    func listenerRestart() async throws {
        defer { cleanUp() }
        let (model, server) = try await app()
        _ = try await queueTwo(model)
        _ = try await model.sendBatch()
        let batch = try #require(model.batches.first)
        let first = await server.reply(to: ControlRequest.wait(timeoutSeconds: 0).sent(by: Self.listener))
        #expect(first.delivered?.batchID == batch.id)

        // The same session waits again before it works on the batch: nothing for it.
        #expect(await server.reply(to: ControlRequest.wait(timeoutSeconds: 0).sent(by: Self.listener)).reply == .ranOut)
        #expect(model.listeners.outbox.taken.map(\.batchID) == [batch.id])

        // The listener restarts: another holder key.
        let again = await server.reply(to: ControlRequest.wait(timeoutSeconds: 0).sent(by: Self.restarted))

        #expect(again.delivered == first.delivered)
        #expect(again.reply.output == first.reply.output)
        #expect(model.listeners.outbox.taken.map(\.batchID) == [batch.id])
        #expect(model.listeners.outbox.pending.isEmpty)
        #expect(model.listeners.outbox.session?.key == Self.restarted.key)
        #expect(model.comments.map(\.state) == [.sent, .sent])
    }

    @Test("a batch whose reply couldn't be written is first in line again, and the next wait gets it")
    func undelivered() async throws {
        defer { cleanUp() }
        let (model, server) = try await app()
        _ = try await queueTwo(model)
        _ = try await model.sendBatch()
        let lost = await server.reply(to: ControlRequest.wait(timeoutSeconds: 0).sent(by: Self.listener))

        server.undelivered(lost)

        #expect(model.listeners.outbox.taken.isEmpty)
        #expect(model.listeners.outbox.pending == [try #require(lost.delivered)])
        let again = await server.reply(to: ControlRequest.wait(timeoutSeconds: 0).sent(by: Self.listener))
        #expect(again.reply.output == lost.reply.output)
    }

    // MARK: - Over the socket

    /// A folder short enough for a socket's path.
    private var socketFolder: URL {
        URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("video-review-\(UUID().uuidString.prefix(8))", isDirectory: true)
    }

    @Test("the listener's client gets the batch over the real socket while the operator sends it")
    func overTheSocket() async throws {
        defer { cleanUp() }
        let folder = socketFolder
        defer { try? FileManager.default.removeItem(at: folder) }
        let (model, server) = try await app(socket: ControlSocket.url(in: folder))
        try server.start()
        defer { server.stop() }
        let socket = server.socket
        _ = try await queueTwo(model)

        async let waited = LeaseServerTests.sending {
            ControlClient(socket: socket, holder: Self.listener, transport: UnixSocketTransport()).send(.wait(timeoutSeconds: 30))
        }
        await eventually { model.listeners.outbox.isWaitOpen }
        let sent = await LeaseServerTests.sending {
            ControlClient(socket: socket, holder: Self.operatorAgent, transport: UnixSocketTransport()).send(.batchSend)
        }

        let reply = try await waited.get()
        #expect(try sent.get().ok)
        #expect(reply.ok)
        #expect((try object(reply.output)["batch"] as? [String: String])?["id"] == model.batches.first?.id.text)
        #expect(model.listeners.outbox.taken.count == 1)
    }

    @Test("a wait whose client goes away is closed: the listener no longer waits, and a batch sent then waits for the next one")
    func clientGoesAway() async throws {
        defer { cleanUp() }
        let folder = socketFolder
        defer { try? FileManager.default.removeItem(at: folder) }
        let (model, server) = try await app(socket: ControlSocket.url(in: folder))
        try server.start()
        defer { server.stop() }

        // A `video-review wait` that's stopped: it sent its request, then its process ended.
        let descriptor = UnixSocket.make()
        let address = try #require(UnixSocket.address(server.socket.path))
        #expect(UnixSocket.connectSocket(descriptor, to: address) == 0)
        #expect(UnixSocket.writeAll(descriptor, ControlRequest.wait(timeoutSeconds: nil).sent(by: Self.listener)))
        UnixSocket.finishWriting(descriptor)
        await eventually { model.listeners.outbox.isWaitOpen }
        #expect(model.listeners.outbox.isWaitOpen)
        // Half-closed isn't gone: the wait stays open while its client reads.
        try await Task.sleep(for: .milliseconds(1200))
        #expect(model.listeners.outbox.isWaitOpen)

        close(descriptor)
        await eventually { !model.listeners.outbox.isWaitOpen }

        #expect(!model.listeners.outbox.isWaitOpen)
        _ = try await model.addComment(text: "After the listener left", at: 3)
        _ = try await model.sendBatch()
        #expect(model.listeners.outbox.pending.count == 1)
        #expect(model.listeners.outbox.taken.isEmpty)
    }
}

@Suite("The rail's words")
@MainActor
struct RailWordsTests {
    @Test("the presence pill says whether an agent listens, who, and what happens to a batch sent now")
    func pill() {
        let listening = PresencePill(presence: .listening, session: "Claude Code", pendingBatches: 0)
        #expect(listening.title == "Agent listening")
        #expect(listening.detail == "Claude Code")
        #expect(listening.text == "Agent listening · Claude Code")

        let working = PresencePill(presence: .working, session: "Claude Code", pendingBatches: 2)
        #expect(working.title == "Agent working")
        #expect(working.detail == "Claude Code · 2 batches waiting")

        let absent = PresencePill(presence: .absent, session: nil, pendingBatches: 0)
        #expect(absent.title == "No agent listening")
        #expect(absent.detail == "a batch will wait")
        // An agent that left is still named by its last wait, but it isn't there.
        #expect(PresencePill(presence: .absent, session: "Claude Code", pendingBatches: 1).detail == "1 batch waiting")
    }

    @Test("the rail groups the cards: the queue first, then each batch from the newest, numbered as the markers are")
    func groups() throws {
        var review = VideoReview(video: VideoInfo(contentHash: "abc", title: "sample", duration: 21.233, path: "/sample.mp4"))
        func id(_ kind: String, _ number: Int) -> ItemID { ItemID("\(kind)-0000000\(number)")! }
        try review.addComment(id: id("c", 1), time: 10, text: "First batch, later")
        try review.addComment(id: id("c", 2), time: 2, text: "First batch, earlier")
        try review.send(batchID: id("b", 1), at: Date(timeIntervalSince1970: 0))
        try review.addComment(id: id("c", 3), time: 5, text: "Second batch")
        try review.send(batchID: id("b", 2), at: Date(timeIntervalSince1970: 60))
        try review.addComment(id: id("c", 4), time: 1, text: "Queued")

        let groups = RailView.groups(comments: review.comments, batches: review.batches)

        #expect(groups.map(\.id) == ["queue", "b-00000002", "b-00000001"])
        #expect(groups.map { $0.cards.map(\.comment.id.text) } == [["c-00000004"], ["c-00000003"], ["c-00000002", "c-00000001"]])
        // Numbers are the comments' places in time order: 1 s, 2 s, 5 s, 10 s.
        #expect(groups.map { $0.cards.map(\.number) } == [[1], [3], [2, 4]])
        #expect(RailView.progress(of: groups[2].cards.map(\.comment)) == "2 comments")
        #expect(RailView.progress(of: groups[1].cards.map(\.comment)) == "1 comment")

        // With everything sent the queue's group is still there, empty.
        try review.send(batchID: id("b", 3), at: Date(timeIntervalSince1970: 120))
        #expect(RailView.groups(comments: review.comments, batches: review.batches).first?.cards.isEmpty == true)
    }
}
