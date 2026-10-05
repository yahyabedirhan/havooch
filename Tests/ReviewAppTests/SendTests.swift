import Darwin
import Foundation
@testable import ReviewApp
import ReviewCore
import ReviewLease
import ReviewWire
import Testing

/// Sends from the person to the listener: the app's model on the fixture
/// video and the control server in front of it, asked as an operator and a
/// listener ask it. No window; the real socket for the last two tests only.
@Suite("Sending to a listener", .serialized)
struct SendDeliveryTests {
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
        try await model.open(MessageTests.fixture)
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

    /// Two queued messages: one on the frame at 10 s (#1), one on a region
    /// at 12.5 s (#2).
    private func queueTwo(
        _ model: AppModel
    ) async throws -> ((message: StateReport.Message, thread: StateReport.Thread), (message: StateReport.Message, thread: StateReport.Thread)) {
        let first = try await model.addMessage(text: "Too fast here", at: 10)
        let second = try await model.addMessage(text: "This box", at: 12.5, region: try Region(x: 0.25, y: 0.2, w: 0.3, h: 0.25))
        return (first, second)
    }

    /// The person's messages of the open video, in the threads' order.
    private func work(_ model: AppModel) -> [Message] {
        model.threads.flatMap { $0.messages.filter(\.isWork) }
    }

    // MARK: - With a listener waiting

    @Test("send with a wait open: the wait answers with the send as its payload, and every image is on disk")
    func sendToAWaitingListener() async throws {
        defer { cleanUp() }
        let (model, server) = try await app()
        let wait = waiting(server)
        await eventually { model.listeners.outbox.isWaitOpen }
        #expect(model.listeners.presence(at: Date()) == .listening)
        let (first, second) = try await queueTwo(model)

        let sent = await server.reply(to: ControlRequest.send.sent(by: Self.operatorAgent))
        let answer = await wait.value

        let send = try #require(model.sends.first)
        #expect(sent.reply == .done("\(send.id) sent: 2 messages on 2 threads, taken by the listener\n"))
        #expect(answer.reply.ok)
        #expect(answer.delivered == SendRef(sendID: send.id, contentHash: try #require(model.video?.contentHash)))

        let payload = try object(answer.reply.output)
        #expect(Set(payload.keys) == ["send", "video", "context", "messages"])
        let sendPart = try #require(payload["send"] as? [String: String])
        #expect(sendPart["id"] == send.id.text)
        #expect(ItemID(send.id.text)?.kind == .send)
        #expect(ISO8601DateFormatter().date(from: try #require(sendPart["sentAt"])) != nil)
        #expect(payload["video"] as? [String: AnyHashable] == [
            "path": MessageTests.fixture.standardizedFileURL.path, "contentHash": try #require(model.video?.contentHash),
            "duration": 21.233, "title": "sample",
        ])
        // The fixture's sidecar, on this session's first send.
        #expect(payload["context"] as? String == ContextReader.sidecar(beside: MessageTests.fixture)?.text)
        let messages = try #require(payload["messages"] as? [[String: Any]])
        #expect(messages.count == 2)
        #expect(messages[0].filter { $0.key != "transcript" } as? [String: AnyHashable] == [
            "id": first.message.id, "threadId": first.thread.id, "threadNumber": 1, "time": 10, "text": "Too fast here",
            "keyframePath": try #require(first.thread.keyframePath), "region": NSNull(), "cropPath": NSNull(),
        ])
        // The fixture's narration, from its voiceover.json.
        #expect((messages[0]["transcript"] as? [[String: Any]])?.count == 3)
        #expect(messages[1]["id"] as? String == second.message.id)
        #expect(messages[1]["threadNumber"] as? Int == 2)
        #expect(messages[1]["time"] as? Double == 12.5)
        #expect(messages[1]["region"] as? [String: Double] == ["x": 0.25, "y": 0.2, "w": 0.3, "h": 0.25])
        #expect(messages[1]["keyframePath"] as? String == second.thread.keyframePath)
        #expect(messages[1]["cropPath"] as? String == second.message.cropPath)
        for path in [first.thread.keyframePath, second.thread.keyframePath, second.message.cropPath] {
            let path = try #require(path)
            #expect(path.hasPrefix(support.path + "/"))
            #expect(FileManager.default.fileExists(atPath: path))
        }

        // The listener has the send: it works, and waits no longer.
        #expect(model.listeners.outbox.taken.map(\.sendID) == [send.id])
        #expect(model.listeners.outbox.pending.isEmpty)
        #expect(model.listeners.presence(at: Date()) == .working)
    }

    @Test("sent messages are sent in the state report, name their send, and leave the queue")
    func sentInState() async throws {
        defer { cleanUp() }
        let (model, server) = try await app()
        let (first, second) = try await queueTwo(model)
        _ = await server.reply(to: ControlRequest.send.sent(by: Self.operatorAgent))

        let state = try object(await server.reply(to: ControlRequest.state.sent(by: Self.listener, json: true)).reply.output)
        let threads = try #require(state["threads"] as? [[String: Any]])
        let messages = threads.flatMap { ($0["messages"] as? [[String: Any]]) ?? [] }
        let send = try #require((state["sends"] as? [[String: Any]])?.first)
        #expect(threads.map { $0["state"] as? String } == [nil, "sent", "sent"])
        #expect(messages.map { $0["state"] as? String } == ["sent", "sent"])
        #expect(messages.map { $0["sendId"] as? String } == [send["id"] as? String, send["id"] as? String])
        #expect(send["messageIds"] as? [String] == [first.message.id, second.message.id])
        #expect(send["threadIds"] as? [String] == [first.thread.id, second.thread.id])
        #expect(state["queue"] as? [String] == [])
        #expect(work(model).map(\.state) == [.sent, .sent])
        #expect(!model.canSend)
        // A sent message is a record.
        let edit = await server.reply(to: ControlRequest.commentEdit(id: first.message.id, text: "new").sent(by: Self.operatorAgent))
        #expect(edit.reply == .refused("\(first.message.id) is sent, and only a queued message can change"))
        let delete = await server.reply(to: ControlRequest.commentDelete(id: first.message.id).sent(by: Self.operatorAgent))
        #expect(!delete.reply.ok)
    }

    // MARK: - With no listener

    @Test("a send made before any wait waits in line, and the next wait returns it at once")
    func sendBeforeAnyWait() async throws {
        defer { cleanUp() }
        let (model, server) = try await app()
        _ = try await queueTwo(model)

        let sent = await server.reply(to: ControlRequest.send.sent(by: Self.operatorAgent))

        let send = try #require(model.sends.first)
        #expect(sent.reply == .done("\(send.id) sent: 2 messages on 2 threads, waiting for a listener\n"))
        #expect(model.listeners.outbox.pending.map(\.sendID) == [send.id])
        #expect(model.listeners.presence(at: Date()) == .absent)
        var state = try object(await server.reply(to: ControlRequest.state.sent(by: Self.listener, json: true)).reply.output)
        #expect(state["listener"] as? [String: AnyHashable] == [
            "presence": "absent", "waitOpen": false, "session": NSNull(), "pendingSends": 1, "takenSends": 0,
        ])

        let answer = await server.reply(to: ControlRequest.wait(timeoutSeconds: 0).sent(by: Self.listener))

        let payload = try object(answer.reply.output)
        #expect((payload["send"] as? [String: String])?["id"] == send.id.text)
        #expect((payload["messages"] as? [[String: Any]])?.count == 2)
        state = try object(await server.reply(to: ControlRequest.state.sent(by: Self.listener, json: true)).reply.output)
        #expect(state["listener"] as? [String: AnyHashable] == [
            "presence": "working", "waitOpen": false, "session": "Claude Code", "pendingSends": 0, "takenSends": 1,
        ])
        #expect(await server.reply(to: ControlRequest.state.sent(by: Self.listener)).reply.output
            .contains("listener: working (Claude Code), 0 sends waiting, 1 taken\n"))
    }

    @Test("sends go out first in, first out, one per wait")
    func oneSendPerWait() async throws {
        defer { cleanUp() }
        let (model, server) = try await app()
        _ = try await model.addMessage(text: "First", at: 3)
        _ = try await model.sendQueue()
        _ = try await model.addMessage(text: "Second", at: 5)
        _ = try await model.sendQueue()
        let ids = model.sends.map(\.id.text)

        var got: [String?] = []
        for _ in 0..<2 {
            let answer = await server.reply(to: ControlRequest.wait(timeoutSeconds: 0).sent(by: Self.listener))
            got.append((try object(answer.reply.output)["send"] as? [String: String])?["id"])
        }
        #expect(got == ids)
        #expect(await server.reply(to: ControlRequest.wait(timeoutSeconds: 0).sent(by: Self.listener)).reply == .ranOut)
    }

    @Test("a send with nothing queued is refused, and no send is made")
    func nothingQueued() async throws {
        defer { cleanUp() }
        let (model, server) = try await app()
        let sent = await server.reply(to: ControlRequest.send.sent(by: Self.operatorAgent))
        #expect(!sent.reply.ok)
        #expect(sent.reply.error.hasPrefix("no message is queued"))
        #expect(model.sends.isEmpty)
        #expect(model.listeners.outbox.pending.isEmpty)
    }

    // MARK: - The person's key

    @Test("Cmd+Return goes the same way as send, and takes the words in the popover with it")
    func sendFromTheKey() async throws {
        defer { cleanUp() }
        let (model, _) = try await app()
        _ = try await model.addMessage(text: "Queued", at: 3)
        try await model.seek(to: 8)
        model.startDraft()
        model.draft?.text = "Still in the box"
        #expect(model.sendCount == 2)

        // What the key and the Send button call.
        model.send()
        await eventually { !model.sends.isEmpty }

        #expect(model.draft == nil)
        #expect(work(model).map(\.text) == ["Queued", "Still in the box"])
        #expect(work(model).map(\.state) == [.sent, .sent])
        #expect(model.sends.count == 1)
        #expect(model.listeners.outbox.pending.count == 1)
        #expect(model.sendCount == 0)

        // With nothing to send the key does nothing: no send, no problem shown.
        model.send()
        try await Task.sleep(for: .milliseconds(50))
        #expect(model.sends.count == 1)
        #expect(model.problem == nil)
    }

    @Test("a message whose keyframe is still being written when Cmd+Return is pressed joins the send")
    func sendRightAfterReturn() async throws {
        defer { cleanUp() }
        let (model, _) = try await app()
        try await model.seek(to: 8)
        model.startDraft()
        model.draft?.text = "Just committed"
        model.commitDraft()
        #expect(work(model).isEmpty)
        #expect(model.canSend)

        model.send()
        await eventually { !model.sends.isEmpty }

        #expect(work(model).map(\.state) == [.sent])
        #expect(model.sends.first?.messageIDs == work(model).map(\.id))
    }

    // MARK: - A wait that ends with no send

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
        _ = try await model.addMessage(text: "For the newer one", at: 3)
        _ = try await model.sendQueue()
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

    // MARK: - A send that goes back

    @Test("a wait from a new listener session gets the send the last one took and didn't finish; the same session doesn't")
    func listenerRestart() async throws {
        defer { cleanUp() }
        let (model, server) = try await app()
        _ = try await queueTwo(model)
        _ = try await model.sendQueue()
        let send = try #require(model.sends.first)
        let first = await server.reply(to: ControlRequest.wait(timeoutSeconds: 0).sent(by: Self.listener))
        #expect(first.delivered?.sendID == send.id)

        // The same session waits again before it works on the send: nothing for it.
        #expect(await server.reply(to: ControlRequest.wait(timeoutSeconds: 0).sent(by: Self.listener)).reply == .ranOut)
        #expect(model.listeners.outbox.taken.map(\.sendID) == [send.id])

        // The listener restarts: another holder key.
        let again = await server.reply(to: ControlRequest.wait(timeoutSeconds: 0).sent(by: Self.restarted))

        #expect(again.delivered == first.delivered)
        #expect(again.reply.output == first.reply.output)
        #expect(model.listeners.outbox.taken.map(\.sendID) == [send.id])
        #expect(model.listeners.outbox.pending.isEmpty)
        #expect(model.listeners.outbox.session?.key == Self.restarted.key)
        #expect(work(model).map(\.state) == [.sent, .sent])
    }

    @Test("a send whose reply couldn't be written is first in line again, and the next wait gets it")
    func undelivered() async throws {
        defer { cleanUp() }
        let (model, server) = try await app()
        _ = try await queueTwo(model)
        _ = try await model.sendQueue()
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

    @Test("the listener's client gets the send over the real socket while the operator sends it")
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
            ControlClient(socket: socket, holder: Self.operatorAgent, transport: UnixSocketTransport()).send(.send)
        }

        let reply = try await waited.get()
        #expect(try sent.get().ok)
        #expect(reply.ok)
        #expect((try object(reply.output)["send"] as? [String: String])?["id"] == model.sends.first?.id.text)
        #expect(model.listeners.outbox.taken.count == 1)
    }

    @Test("a wait whose client goes away is closed: the listener no longer waits, and a send made then waits for the next one")
    func clientGoesAway() async throws {
        defer { cleanUp() }
        let folder = socketFolder
        defer { try? FileManager.default.removeItem(at: folder) }
        let (model, server) = try await app(socket: ControlSocket.url(in: folder))
        try server.start(heartbeat: .milliseconds(200))
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
        // Meanwhile the held wait got the heartbeat: spaces, and nothing else.
        var buffer = [UInt8](repeating: 0, count: 64)
        let count = buffer.withUnsafeMutableBytes { recv(descriptor, $0.baseAddress, $0.count, Int32(MSG_DONTWAIT)) }
        #expect(count > 0)
        #expect(buffer.prefix(max(count, 0)).allSatisfy { $0 == UInt8(ascii: " ") })

        close(descriptor)
        await eventually { !model.listeners.outbox.isWaitOpen }

        #expect(!model.listeners.outbox.isWaitOpen)
        _ = try await model.addMessage(text: "After the listener left", at: 3)
        _ = try await model.sendQueue()
        #expect(model.listeners.outbox.pending.count == 1)
        #expect(model.listeners.outbox.taken.isEmpty)
    }
}

@Suite("The rail's words")
struct RailWordsTests {
    @Test("the presence pill says whether an agent listens, who, and what happens to a send made now")
    func pill() {
        let listening = PresencePill(presence: .listening, session: "Claude Code", pendingSends: 0)
        #expect(listening.title == "Agent listening")
        #expect(listening.detail == "Claude Code")
        #expect(listening.text == "Agent listening · Claude Code")

        let working = PresencePill(presence: .working, session: "Claude Code", pendingSends: 2)
        #expect(working.title == "Agent working")
        #expect(working.detail == "Claude Code · 2 sends waiting")

        let absent = PresencePill(presence: .absent, session: nil, pendingSends: 0)
        #expect(absent.title == "No agent listening")
        #expect(absent.detail == "a send will wait")
        // An agent that left is still named by its last wait, but it isn't there.
        #expect(PresencePill(presence: .absent, session: "Claude Code", pendingSends: 1).detail == "1 send waiting")
    }

    @Test("a thread's conversation is cut into the person's messages, as rows, and runs of the agent's messages and answers")
    func parts() throws {
        var review = VideoReview(video: VideoInfo(contentHash: "f92cbb2a00", title: "sample", duration: 21.233, path: "/sample.mp4"))
        let now = Date(timeIntervalSince1970: 0)
        let thread = try review.write(text: "First", at: 10, now: now).thread.id
        try review.write(text: "Second", at: 10, now: now)
        try review.send(at: now)
        try review.reply(on: thread, text: "Looking", now: now)
        try review.ask(on: thread, question: "Which?", now: now)
        try review.answer(thread, text: "This one", now: now)
        try review.write(text: "Third", at: 10, now: now)

        let parts = RailView.parts(of: try #require(review.thread(thread)).messages)

        #expect(parts.map(\.id) == ["m-f92cbb2a-1", "m-f92cbb2a-2", "talk-m-f92cbb2a-3", "m-f92cbb2a-6"])
        guard case .talk(let talk) = parts[2] else { Issue.record("not a run of talk"); return }
        #expect(talk.map(\.kind) == [.message, .question, .answer])
    }
}
