import Foundation
@testable import ReviewApp
import ReviewCore
import ReviewLease
import ReviewWire
import Testing

/// The listener's whole round over the real socket: the app's model on the
/// fixture video and the control server listening on `control.sock`, asked
/// by `ControlClient`s as the `havooch` command asks it, an operator
/// and a listener in two shells.
@Suite("The listener over the real socket", .serialized)
struct ListenerSocketTests {
    nonisolated static let operatorAgent = Holder(key: "operator", name: "Claude Code", place: "/work")
    nonisolated static let listener = Holder(key: "listener-1", name: "Mate", place: "/shop")
    nonisolated static let restarted = Holder(key: "listener-2", name: "Mate", place: "/shop")

    let support = FileManager.default.temporaryDirectory
        .appendingPathComponent("havooch-tests-\(UUID().uuidString)", isDirectory: true)
    /// A folder short enough for a socket's path.
    let folder = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("havooch-\(UUID().uuidString.prefix(8))", isDirectory: true)

    private func cleanUp() {
        try? FileManager.default.removeItem(at: support)
        try? FileManager.default.removeItem(at: folder)
    }

    /// The model with the fixture open, two messages queued on #1 and #2,
    /// and the server listening in front of it.
    private struct Running {
        var model: AppModel
        var server: ControlServer
        var one: String
        var two: String
        var first: String
        var second: String
    }

    private func running() async throws -> Running {
        let model = AppModel(environment: [SupportFolder.overrideVariable: support.path])
        try await model.open(MessageTests.fixture)
        let server = ControlServer(
            socket: ControlSocket.url(in: folder), app: model, listeners: model.listeners,
            screenshotter: ControlServerTests.FakeScreenshotter(), quit: {}
        )
        try server.start()
        let first = try await model.addMessage(text: "Too fast here", at: 10)
        let second = try await model.addMessage(text: "This box", at: 12.5, region: try Region(x: 0.25, y: 0.2, w: 0.3, h: 0.25))
        return Running(
            model: model, server: server, one: first.thread.id, two: second.thread.id,
            first: first.message.id, second: second.message.id
        )
    }

    /// One `havooch` command as `holder`, over the socket.
    private func command(
        _ request: ControlRequest, as holder: Holder, json: Bool = false, _ app: Running
    ) async throws -> ControlReply {
        let socket = app.server.socket
        return try await LeaseServerTests.sending {
            ControlClient(socket: socket, holder: holder, json: json, transport: UnixSocketTransport()).send(request)
        }.get()
    }

    private func object(_ text: String) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    }

    private func eventually(_ condition: () -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(10)
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    /// `state --json` as the listener asks it.
    private func state(_ app: Running) async throws -> [String: Any] {
        try object(try await command(.state, as: Self.listener, json: true, app).output)
    }

    private func presence(_ app: Running) async throws -> String? {
        (try await state(app)["listener"] as? [String: Any])?["presence"] as? String
    }

    /// The listener's `wait` in its own shell, and the operator's `send`
    /// while it's held: the send's payload.
    private func waitThenSend(_ app: Running, as holder: Holder = listener) async throws -> [String: Any] {
        let socket = app.server.socket
        async let waited = LeaseServerTests.sending {
            ControlClient(socket: socket, holder: holder, transport: UnixSocketTransport()).send(.wait(timeoutSeconds: 30))
        }
        await eventually { app.model.listeners.outbox.isWaitOpen }
        #expect(try await presence(app) == "listening")
        #expect(try await command(.send, as: Self.operatorAgent, app).ok)
        let reply = try await waited.get()
        #expect(reply.ok)
        // Taken once the socket wrote the reply.
        await eventually { app.model.listeners.outbox.inFlight.isEmpty && !app.model.listeners.outbox.taken.isEmpty }
        return try object(reply.output)
    }

    private func work(_ app: Running) -> [MessageState?] {
        app.model.threads.flatMap { $0.messages.filter(\.isWork).map(\.state) }
    }

    @Test("ack moves the send to acknowledged and posts its words on General; status moves each message and refuses a move back; presence goes absent, listening, working")
    func ackAndStatus() async throws {
        defer { cleanUp() }
        let app = try await running()
        defer { app.server.stop() }
        #expect(try await presence(app) == "absent")

        let payload = try await waitThenSend(app)
        let send = try #require((payload["send"] as? [String: String])?["id"])
        #expect(try await presence(app) == "working")

        let ack = try await command(.ack(sendID: send, text: "On it"), as: Self.listener, app)
        #expect(ack == .done("\(send) acknowledged, 2 messages\n"))
        #expect(work(app) == [.acknowledged, .acknowledged])
        let general = try #require(app.model.threads.first)
        #expect(general.messages.map(\.author) == [.agent])
        #expect(general.messages.map(\.text) == ["On it"])

        #expect(try await command(.status(messageID: app.first, state: .working), as: Self.listener, app).ok)
        #expect(try await command(.status(messageID: app.first, state: .done), as: Self.listener, app).ok)
        let back = try await command(.status(messageID: app.first, state: .working), as: Self.listener, app)
        #expect(!back.ok)
        #expect(back.error.contains("can't move to working"))
        #expect(work(app) == [.done, .acknowledged])

        let reply = try await command(.reply(thread: app.two, text: "Moved it"), as: Self.listener, app)
        #expect(reply.ok)
        let replied = try #require(app.model.threads.last?.messages.last)
        #expect(replied.author == .agent)
        #expect(replied.text == "Moved it")

        // The send's last message finishes it: nothing is taken any more.
        #expect(try await command(.status(messageID: app.second, state: .failed), as: Self.listener, app).ok)
        #expect(app.model.listeners.outbox.taken.isEmpty)
        let listener = try #require(try await state(app)["listener"] as? [String: Any])
        #expect(listener["takenSends"] as? Int == 0)
        #expect(listener["session"] as? String == "Mate")
    }

    @Test("ask is held until thread answer, which goes to it at once and never into the queue")
    func askAndAnswer() async throws {
        defer { cleanUp() }
        let app = try await running()
        defer { app.server.stop() }
        _ = try await waitThenSend(app)
        let socket = app.server.socket
        let one = app.one

        async let asked = LeaseServerTests.sending {
            ControlClient(socket: socket, holder: Self.listener, transport: UnixSocketTransport())
                .send(.ask(thread: one, question: "Which part?", waitSeconds: 30))
        }
        await eventually { app.model.listeners.outbox.openAsks == 1 }
        #expect(app.model.threads[1].openQuestion?.text == "Which part?")
        // A second question on the thread is refused while the first is open.
        #expect(try await command(.ask(thread: one, question: "And?", waitSeconds: 0), as: Self.listener, app).ok == false)

        let answered = try await command(.threadAnswer(thread: one, text: "The intro"), as: Self.operatorAgent, app)
        #expect(answered.ok)
        #expect(try await asked.get() == .done("The intro\n"))
        #expect(app.model.listeners.outbox.openAsks == 0)
        #expect(app.model.threads[1].openQuestion == nil)
        #expect(app.model.threads[1].messages.map(\.kind) == [.message, .question, .answer])
        #expect(app.model.desk.review?.queue.isEmpty == true)
        #expect(app.model.listeners.outbox.pending.isEmpty)
        // No question is open now: an answer is refused.
        #expect(try await command(.threadAnswer(thread: one, text: "Again"), as: Self.operatorAgent, app).ok == false)
    }

    @Test("a follow-up on a finished thread makes it active again, and its send has the earlier messages in history and no context")
    func followUp() async throws {
        defer { cleanUp() }
        let app = try await running()
        defer { app.server.stop() }
        let first = try await waitThenSend(app)
        #expect(first["context"] is String)
        let send = try #require((first["send"] as? [String: String])?["id"])
        _ = try await command(.ack(sendID: send, text: nil), as: Self.listener, app)
        _ = try await command(.reply(thread: app.one, text: "Slowed it down"), as: Self.listener, app)
        _ = try await command(.status(messageID: app.first, state: .done), as: Self.listener, app)
        _ = try await command(.status(messageID: app.second, state: .done), as: Self.listener, app)
        let threadState = { (app: Running) async throws -> String? in
            let threads = try #require(try await state(app)["threads"] as? [[String: Any]])
            return threads.first { $0["id"] as? String == app.one }?["state"] as? String
        }
        #expect(try await threadState(app) == "done")

        let added = try await command(
            .commentAdd(text: "Still too fast", at: nil, region: nil, thread: app.one), as: Self.operatorAgent, json: true, app
        )
        #expect(added.ok)
        let followUp = try #require((try object(added.output)["message"] as? [String: Any])?["id"] as? String)
        #expect(try await threadState(app) == "queued")

        let payload = try await waitThenSend(app)
        #expect(payload["context"] is NSNull)
        let threads = try #require(payload["threads"] as? [[String: Any]])
        #expect(threads.map { $0["id"] as? String } == [app.one])
        let history = try #require(threads[0]["history"] as? [[String: Any]])
        #expect(history.map { $0["author"] as? String } == ["person", "agent"])
        #expect(history.map { $0["text"] as? String } == ["Too fast here", "Slowed it down"])
        #expect((threads[0]["messages"] as? [[String: Any]])?.map { $0["id"] as? String } == [followUp])
        #expect(try await threadState(app) == "sent")
    }

    @Test("a listener that restarts gets the send it took and didn't finish, its unfinished messages sent again")
    func listenerRestart() async throws {
        defer { cleanUp() }
        let app = try await running()
        defer { app.server.stop() }
        let first = try await waitThenSend(app)
        let send = try #require((first["send"] as? [String: String])?["id"])
        _ = try await command(.ack(sendID: send, text: "On it"), as: Self.listener, app)
        _ = try await command(.status(messageID: app.first, state: .done), as: Self.listener, app)
        _ = try await command(.status(messageID: app.second, state: .working), as: Self.listener, app)

        // The listener's process ends; a new one, another holder, waits.
        let again = try await command(.wait(timeoutSeconds: 5), as: Self.restarted, app)

        #expect(again.ok)
        let payload = try object(again.output)
        #expect((payload["send"] as? [String: String])?["id"] == send)
        // The finished thread is left out; the unfinished message is delivered again, with the context.
        let threads = try #require(payload["threads"] as? [[String: Any]])
        #expect(threads.map { $0["id"] as? String } == [app.two])
        #expect((threads[0]["messages"] as? [[String: Any]])?.map { $0["id"] as? String } == [app.second])
        #expect(payload["context"] is String)
        #expect(work(app) == [.done, .sent])
        let listener = try #require(try await state(app)["listener"] as? [String: Any])
        #expect(listener["presence"] as? String == "working")
        #expect(app.model.listeners.outbox.session?.key == Self.restarted.key)
        #expect(try await command(.ack(sendID: send, text: nil), as: Self.restarted, app).ok)
        #expect(work(app) == [.done, .acknowledged])
    }
}
