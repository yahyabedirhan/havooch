import Darwin
import Foundation
@testable import ReviewApp
import ReviewCore
import ReviewLease
import ReviewWire
import Testing

/// The agent's answers in the player: the app's model on the fixture video
/// and the control server in front of it, asked as a listener and an
/// operator ask it. No window; the real socket for the last test only.
@Suite("Agent answers and questions in the player", .serialized)
struct AnswerTests {
    nonisolated static let operatorAgent = Holder(key: "operator", name: "Claude Code", place: "/work")
    nonisolated static let listener = Holder(key: "listener-1", name: "Mate", place: "/shop")

    let support = FileManager.default.temporaryDirectory
        .appendingPathComponent("video-review-tests-\(UUID().uuidString)", isDirectory: true)

    private func cleanUp() {
        try? FileManager.default.removeItem(at: support)
    }

    /// What a test works with: the model with the fixture open, the server
    /// in front of it, and a batch of two comments that the listener took.
    private struct Taken {
        var model: AppModel
        var server: ControlServer
        var batch: String
        var first: String
        var second: String
    }

    private func taken(socket: URL = URL(fileURLWithPath: "/nowhere/control.sock")) async throws -> Taken {
        let model = AppModel(environment: [SupportFolder.overrideVariable: support.path])
        try await model.open(CommentTests.fixture)
        let server = ControlServer(
            socket: socket, app: model, listeners: model.listeners, screenshotter: ControlServerTests.FakeScreenshotter(), quit: {}
        )
        let first = try await model.addComment(text: "Too fast here", at: 10)
        let second = try await model.addComment(text: "This box", at: 12.5, region: try Region(x: 0.25, y: 0.2, w: 0.3, h: 0.25))
        let batch = try await model.sendBatch()
        let wait = await server.reply(to: ControlRequest.wait(timeoutSeconds: 0).sent(by: Self.listener))
        #expect(wait.reply.ok)
        return Taken(model: model, server: server, batch: batch.id, first: first.id, second: second.id)
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

    private func listen(_ request: ControlRequest, _ app: Taken, json: Bool = false) async -> ControlReply {
        await app.server.reply(to: request.sent(by: Self.listener, json: json)).reply
    }

    private func operate(_ request: ControlRequest, _ app: Taken, json: Bool = false) async -> ControlReply {
        await app.server.reply(to: request.sent(by: Self.operatorAgent, json: json)).reply
    }

    private func state(_ app: Taken) async throws -> [String: Any] {
        try object(await listen(.state, app, json: true).output)
    }

    private func comments(_ app: Taken) async throws -> [[String: Any]] {
        try #require(try await state(app)["comments"] as? [[String: Any]])
    }

    // MARK: - ack

    @Test("ack sets the comments of the batch to acknowledged, and takes no lease")
    func ack() async throws {
        defer { cleanUp() }
        let app = try await taken()

        let reply = await listen(.ack(batchID: app.batch, text: nil), app)

        #expect(reply == .done("\(app.batch) acknowledged, 2 comments\n"))
        #expect(try await comments(app).map { $0["state"] as? String } == ["acknowledged", "acknowledged"])
        #expect(app.model.comments.map(\.state) == [.acknowledged, .acknowledged])
        #expect(app.model.batches.first?.messages.isEmpty == true)
        #expect(app.server.lease.current(at: Date()) == nil)
        // The acknowledgement shows in the player.
        #expect(app.model.notices.map(\.kind) == [.acknowledgement])
        #expect(app.model.notices.first?.title(number: nil) == "Mate has your batch")
        #expect(app.model.notices.first?.text == "It got your 2 comments.")
    }

    @Test("ack with text adds the agent's message for the full batch, in state and as a notice")
    func ackWithText() async throws {
        defer { cleanUp() }
        let app = try await taken()

        let reply = try object(await listen(.ack(batchID: app.batch, text: "On it"), app, json: true).output)

        let batch = try #require(reply["batch"] as? [String: Any])
        let messages = try #require(batch["messages"] as? [[String: Any]])
        #expect(messages.count == 1)
        #expect(messages[0]["author"] as? String == "agent")
        #expect(messages[0]["kind"] as? String == "message")
        #expect(messages[0]["text"] as? String == "On it")
        let listed = try #require((try await state(app)["batches"] as? [[String: Any]])?.first?["messages"] as? [[String: Any]])
        #expect(listed.map { $0["id"] as? String } == messages.map { $0["id"] as? String })
        #expect(app.model.notices.first?.text == "On it")
        #expect(app.model.notices.first?.subject == .batch(try #require(ItemID(app.batch))))
    }

    @Test("ack of an id that names no batch is refused, and changes nothing")
    func ackUnknown() async throws {
        defer { cleanUp() }
        let app = try await taken()
        for id in ["b-00000000", app.first, "nonsense"] {
            let reply = await listen(.ack(batchID: id, text: "On it"), app)
            #expect(reply == .refused("no batch `\(id)`; `video-review state --json` lists the batches"))
        }
        #expect(app.model.comments.map(\.state) == [.sent, .sent])
        #expect(app.model.notices.isEmpty)
    }

    // MARK: - status

    @Test("each status shows on its comment, and the batch's last finished comment returns the listener to listening")
    func status() async throws {
        defer { cleanUp() }
        let app = try await taken()
        #expect(app.model.listeners.presence(at: Date()) == .working)

        #expect(await listen(.status(commentID: app.first, state: .working), app) == .done("\(app.first) working\n"))
        #expect(app.model.comments.map(\.state) == [.working, .sent])
        #expect(await listen(.status(commentID: app.first, state: .done), app) == .done("\(app.first) done\n"))
        #expect(app.model.listeners.outbox.taken.count == 1)

        let failed = try object(await listen(.status(commentID: app.second, state: .failed), app, json: true).output)
        #expect((failed["comment"] as? [String: Any])?["state"] as? String == "failed")
        #expect((failed["comment"] as? [String: Any])?["id"] as? String == app.second)

        #expect(try await comments(app).map { $0["state"] as? String } == ["done", "failed"])
        #expect(RailView.progress(of: app.model.comments) == "2 of 2 done")
        // Nothing is left of the batch: the listener isn't working any more.
        #expect(app.model.listeners.outbox.taken.isEmpty)
        let listening = app.server
        let wait = Task { await listening.reply(to: ControlRequest.wait(timeoutSeconds: nil).sent(by: Self.listener)) }
        await eventually { app.model.listeners.outbox.isWaitOpen }
        #expect(app.model.listeners.presence(at: Date()) == .listening)
        app.server.stop()
        _ = await wait.value
    }

    @Test("a status that moves a comment back, or names no comment, is refused")
    func statusRefused() async throws {
        defer { cleanUp() }
        let app = try await taken()
        _ = await listen(.status(commentID: app.first, state: .done), app)

        let back = await listen(.status(commentID: app.first, state: .working), app)
        #expect(back == .refused(
            "\(app.first) is done and can't move to working: a comment only moves forward (sent, acknowledged, working, then done or failed)"
        ))
        #expect(await listen(.status(commentID: app.first, state: .failed), app).ok == false)
        // Saying it again changes nothing.
        #expect(await listen(.status(commentID: app.first, state: .done), app).ok)
        for id in ["c-00000000", app.batch, "nonsense"] {
            #expect(await listen(.status(commentID: id, state: .done), app)
                == .refused("no comment `\(id)`; the batch `video-review wait` printed names each comment's id"))
        }
        #expect(app.model.comments.map(\.state) == [.done, .sent])
    }

    // MARK: - reply

    @Test("reply shows in the thread of its comment and as a notice, and marks the comment until the person looks")
    func reply() async throws {
        defer { cleanUp() }
        let app = try await taken()
        let second = try #require(ItemID(app.second))
        #expect(app.model.selection == second)

        let reply = await listen(.reply(id: app.first, text: "Slowed the intro down"), app)

        let message = try #require(app.model.comments[0].thread.first)
        #expect(reply == .done("\(message.id) on \(app.first)\n"))
        #expect(message.author == .agent)
        #expect(message.kind == .message)
        #expect(message.text == "Slowed the intro down")
        #expect(app.model.comments[1].thread.isEmpty)
        let thread = try #require(try await comments(app)[0]["thread"] as? [[String: Any]])
        #expect(thread.count == 1)
        #expect(thread[0]["author"] as? String == "agent")
        #expect(thread[0]["kind"] as? String == "message")
        #expect(thread[0]["id"] as? String == message.id.text)
        #expect(ISO8601DateFormatter().date(from: try #require(thread[0]["at"] as? String)) != nil)

        let notice = try #require(app.model.notices.first)
        #expect(notice.subject == .comment(try #require(ItemID(app.first))))
        #expect(notice.kind == .message)
        #expect(notice.title(number: 1) == "Mate replied on comment 1")
        #expect(notice.text == "Slowed the intro down")
        #expect(notice.expires != nil)
        #expect(app.model.unread == [try #require(ItemID(app.first))])
        #expect(MarkerPin.Badge(app.model.comments[0], unread: app.model.unread) == .unread)

        // A click on the notice: it goes, and the comment is selected and read.
        app.model.openNotice(notice.id)
        #expect(app.model.notices.isEmpty)
        #expect(app.model.selection == ItemID(app.first))
        #expect(app.model.unread.isEmpty)
        #expect(MarkerPin.Badge(app.model.comments[0], unread: app.model.unread) == nil)
    }

    @Test("a reply to a batch id shows as a message for the full batch")
    func replyToBatch() async throws {
        defer { cleanUp() }
        let app = try await taken()

        let reply = try object(await listen(.reply(id: app.batch, text: "Both fixed in one commit"), app, json: true).output)

        let message = try #require(reply["message"] as? [String: Any])
        #expect(message["author"] as? String == "agent")
        #expect(message["kind"] as? String == "message")
        #expect(app.model.batches.first?.messages.map(\.text) == ["Both fixed in one commit"])
        #expect(app.model.comments.allSatisfy { $0.thread.isEmpty })
        #expect(app.model.notices.first?.title(number: nil) == "Mate on the whole batch")
        #expect(app.model.unread.isEmpty)
    }

    @Test("a reply to an id that names nothing, or with no words, is refused")
    func replyRefused() async throws {
        defer { cleanUp() }
        let app = try await taken()
        for id in ["c-00000000", "b-00000000", "m-00000000", "nonsense"] {
            #expect(await listen(.reply(id: id, text: "Hello"), app)
                == .refused("no comment or batch `\(id)`; the batch `video-review wait` printed names their ids"))
        }
        #expect(await listen(.reply(id: app.first, text: "  "), app) == .refused("a message needs text"))
        #expect(app.model.notices.isEmpty)
    }

    @Test("a notice of a message goes by itself; a question's stays")
    func noticesGo() async throws {
        defer { cleanUp() }
        let app = try await taken()
        _ = await listen(.reply(id: app.first, text: "Done"), app)
        _ = await listen(.ask(commentID: app.second, question: "Which box?", waitSeconds: 0), app)
        #expect(app.model.notices.map(\.kind) == [.message, .question])
        #expect(app.model.notices[1].expires == nil)
        #expect(app.model.notices[1].hint == "Click to answer")
        let message = app.model.notices[0]
        #expect(try #require(message.expires).timeIntervalSinceNow <= Notice.life)

        // Its time is up.
        app.model.dismiss(message.id)
        #expect(app.model.notices.map(\.kind) == [.question])
    }

    // MARK: - ask and answer

    @Test("ask --wait exits with the answer that thread answer gives, and the thread keeps each message's author and kind")
    func askAnsweredByTheOperator() async throws {
        defer { cleanUp() }
        let app = try await taken()
        let server = app.server
        let second = app.second
        let asking = Task { await server.reply(to: ControlRequest.ask(commentID: second, question: "Which box?", waitSeconds: 30).sent(by: Self.listener)) }
        await eventually { app.model.listeners.outbox.openAsks == 1 }
        #expect(app.model.comments[1].openQuestion?.text == "Which box?")
        #expect(MarkerPin.Badge(app.model.comments[1], unread: []) == .question)
        #expect(app.model.notices.map(\.kind) == [.question])
        #expect(app.model.notices.first?.title(number: 2) == "Mate asks about comment 2")

        let answered = await operate(.threadAnswer(commentID: app.second, text: "The left one"), app)
        let reply = await asking.value.reply

        #expect(answered == .done("\(app.second) answered\n"))
        #expect(reply == .done("The left one\n"))
        #expect(app.model.listeners.outbox.openAsks == 0)
        #expect(app.model.comments[1].openQuestion == nil)
        // The question's notice goes with its answer, and the thread is read.
        #expect(app.model.notices.isEmpty)
        #expect(app.model.unread.isEmpty)
        let thread = try #require(try await comments(app)[1]["thread"] as? [[String: Any]])
        #expect(thread.map { $0["author"] as? String } == ["agent", "person"])
        #expect(thread.map { $0["kind"] as? String } == ["question", "answer"])
        #expect(thread.map { $0["text"] as? String } == ["Which box?", "The left one"])
        // The operator took the lease for it; the listener never did.
        #expect(app.server.lease.current(at: Date())?.holder.key == "operator")
    }

    @Test("ask --wait exits with the answer the person gives in the answer box, as JSON with --json")
    func askAnsweredByThePerson() async throws {
        defer { cleanUp() }
        let app = try await taken()
        let server = app.server
        let first = app.first
        let asking = Task {
            await server.reply(to: ControlRequest.ask(commentID: first, question: "Which part?", waitSeconds: nil).sent(by: Self.listener, json: true))
        }
        await eventually { app.model.listeners.outbox.openAsks == 1 }

        // The answer box's Return and its button.
        #expect(app.model.answerQuestion(try #require(ItemID(app.first)), text: " The intro "))

        let answer = try #require(try object(await asking.value.reply.output)["answer"] as? [String: Any])
        #expect(answer["text"] as? String == "The intro")
        #expect(answer["author"] as? String == "person")
        #expect(answer["kind"] as? String == "answer")
        #expect(app.model.problem == nil)
        // No lease: the person never needs one.
        #expect(app.server.lease.current(at: Date()) == nil)
    }

    @Test("an ask whose wait runs out answers that it ran out; the question stays open, and a late answer stays in the thread")
    func askRunsOut() async throws {
        defer { cleanUp() }
        let app = try await taken()
        let started = Date()

        let reply = await listen(.ask(commentID: app.first, question: "Which part?", waitSeconds: 1), app)

        #expect(reply == .ranOut)
        #expect(Date().timeIntervalSince(started) >= 1)
        #expect(app.model.listeners.outbox.openAsks == 0)
        #expect(app.model.comments[0].openQuestion != nil)
        #expect(app.model.notices.map(\.kind) == [.question])

        let late = await operate(.threadAnswer(commentID: app.first, text: "The intro"), app)
        #expect(late.ok)
        let thread = try #require(try await comments(app)[0]["thread"] as? [[String: Any]])
        #expect(thread.map { $0["kind"] as? String } == ["question", "answer"])
        #expect(thread.last?["text"] as? String == "The intro")
        #expect(app.model.notices.isEmpty)
    }

    @Test("ask --wait 0 leaves the question and answers at once that it has no answer")
    func askWithoutWaiting() async throws {
        defer { cleanUp() }
        let app = try await taken()
        #expect(await listen(.ask(commentID: app.first, question: "Which part?", waitSeconds: 0), app) == .ranOut)
        #expect(app.model.comments[0].openQuestion?.text == "Which part?")
        #expect(app.model.listeners.outbox.openAsks == 0)
    }

    @Test("a second question while one is open, and an answer with no question, are refused")
    func askAndAnswerRefused() async throws {
        defer { cleanUp() }
        let app = try await taken()
        #expect(await operate(.threadAnswer(commentID: app.first, text: "Yes"), app)
            == .refused("\(app.first) has no open question to answer"))
        _ = await listen(.ask(commentID: app.first, question: "Which part?", waitSeconds: 0), app)

        let second = await listen(.ask(commentID: app.first, question: "And how?", waitSeconds: 30), app)
        #expect(second == .refused(
            "\(app.first) already has an open question; its answer comes in the comment's thread, which `video-review state --json` shows"
        ))
        #expect(app.model.comments[0].thread.count == 1)
        #expect(app.model.listeners.outbox.openAsks == 0)
        #expect(await listen(.ask(commentID: "c-00000000", question: "Why?", waitSeconds: 0), app).ok == false)
        #expect(await operate(.threadAnswer(commentID: "c-00000000", text: "Yes"), app).ok == false)
        #expect(await operate(.threadAnswer(commentID: app.first, text: " "), app) == .refused("a message needs text"))

        // The answer box says why it didn't take an answer.
        #expect(!app.model.answerQuestion(try #require(ItemID(app.second)), text: "Yes"))
        #expect(app.model.problem?.title == "The answer wasn't sent")
    }

    @Test("when the app quits, an open ask ends with no reply, and its question stays in the thread")
    func quitting() async throws {
        defer { cleanUp() }
        let app = try await taken()
        let server = app.server
        let first = app.first
        let asking = Task { await server.reply(to: ControlRequest.ask(commentID: first, question: "Which part?", waitSeconds: nil).sent(by: Self.listener)) }
        await eventually { app.model.listeners.outbox.openAsks == 1 }
        #expect(app.model.listeners.presence(at: Date().addingTimeInterval(3600)) == .working)

        app.server.stop()

        #expect(await asking.value.silent)
        #expect(app.model.listeners.outbox.openAsks == 0)
        #expect(app.model.comments[0].openQuestion != nil)
    }

    @Test("the state lines say how many messages a comment has, and whether a question is open")
    func stateLines() async throws {
        defer { cleanUp() }
        let app = try await taken()
        _ = await listen(.reply(id: app.first, text: "Looking"), app)
        _ = await listen(.ask(commentID: app.first, question: "Which part?", waitSeconds: 0), app)
        let lines = await listen(.state, app).output
        #expect(lines.contains("  \(app.first) 0:10 sent (2 messages, question open): Too fast here\n"))
        #expect(lines.contains(" sent: This box\n"))
    }

    @Test("the listener answers a comment of a video that's no longer the open one: its commands name no video")
    func anotherVideoOpen() async throws {
        defer { cleanUp() }
        let app = try await taken()
        // The same film with other content: another video to the app.
        let other = support.appendingPathComponent("other.mp4")
        var bytes = try Data(contentsOf: CommentTests.fixture)
        bytes.append(Data(repeating: 0, count: 16))
        try bytes.write(to: other)
        let first = try #require(app.model.video?.contentHash)
        try await app.model.open(other)
        #expect(app.model.video?.contentHash != first)
        #expect(app.model.comments.isEmpty)

        #expect(await listen(.ack(batchID: app.batch, text: "On it"), app).ok)
        #expect(await listen(.reply(id: app.first, text: "Done"), app).ok)
        let status = try object(await listen(.status(commentID: app.first, state: .done), app, json: true).output)
        _ = await listen(.ask(commentID: app.second, question: "Which box?", waitSeconds: 0), app)
        #expect(await operate(.threadAnswer(commentID: app.second, text: "The left one"), app).ok)

        let comment = try #require(status["comment"] as? [String: Any])
        #expect(comment["state"] as? String == "done")
        #expect((comment["keyframePath"] as? String)?.contains("/videos/\(first)/frames/") == true)
        let review = try #require(app.model.desk.review(of: first))
        #expect(review.comments.map(\.state) == [.done, .acknowledged])
        #expect(review.comments.map(\.thread.count) == [1, 2])
        #expect(review.batches.first?.messages.count == 1)
        // The open video's review is untouched.
        #expect(app.model.comments.isEmpty)
    }

    // MARK: - Over the socket

    @Test("over the real socket, an ask is held until thread answer, and an ask whose client goes away stops waiting")
    func overTheSocket() async throws {
        defer { cleanUp() }
        let folder = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("video-review-\(UUID().uuidString.prefix(8))", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let app = try await taken(socket: ControlSocket.url(in: folder))
        try app.server.start()
        defer { app.server.stop() }
        let socket = app.server.socket
        let first = app.first

        async let asked = LeaseServerTests.sending {
            ControlClient(socket: socket, holder: Self.listener, transport: UnixSocketTransport())
                .send(.ask(commentID: first, question: "Which part?", waitSeconds: 30))
        }
        await eventually { app.model.listeners.outbox.openAsks == 1 }
        let answered = await LeaseServerTests.sending {
            ControlClient(socket: socket, holder: Self.operatorAgent, transport: UnixSocketTransport())
                .send(.threadAnswer(commentID: first, text: "The intro"))
        }
        #expect(try answered.get().ok)
        #expect(try await asked.get() == .done("The intro\n"))

        // An `ask` that's stopped: it sent its request, then its process ended.
        let descriptor = UnixSocket.make()
        let address = try #require(UnixSocket.address(socket.path))
        #expect(UnixSocket.connectSocket(descriptor, to: address) == 0)
        #expect(UnixSocket.writeAll(descriptor, ControlRequest.ask(commentID: app.second, question: "Which box?", waitSeconds: nil).sent(by: Self.listener)))
        UnixSocket.finishWriting(descriptor)
        await eventually { app.model.listeners.outbox.openAsks == 1 }
        #expect(app.model.listeners.outbox.openAsks == 1)
        close(descriptor)
        await eventually { app.model.listeners.outbox.openAsks == 0 }
        #expect(app.model.listeners.outbox.openAsks == 0)
        #expect(app.model.comments[1].openQuestion?.text == "Which box?")
    }
}

@Suite("The thread's words")
struct ThreadWordsTests {
    static let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func message(_ author: ThreadMessage.Author, _ kind: ThreadMessage.Kind) -> ThreadMessage {
        ThreadMessage(id: ItemID("m-00000001")!, author: author, kind: kind, text: "Words", at: Self.now)
    }

    @Test("a thread message is headed by who said it, and how")
    func headings() {
        #expect(ThreadHeading(message(.agent, .message), agent: "Claude Code").title == "Claude Code")
        #expect(ThreadHeading(message(.agent, .question), agent: "Claude Code").title == "Claude Code asked")
        #expect(ThreadHeading(message(.person, .answer), agent: "Claude Code").title == "You answered")
        #expect(ThreadHeading(message(.agent, .question), agent: "Claude Code").symbol == "questionmark")
    }

    @Test("a notice says who said what about which comment, and only a question stays up")
    func notices() {
        let comment = Notice.Subject.comment(ItemID("c-00000001")!)
        let batch = Notice.Subject.batch(ItemID("b-00000001")!)
        let reply = Notice(subject: comment, kind: .message, agent: "Claude Code", text: "Done", at: Self.now)
        #expect(reply.title(number: 3) == "Claude Code replied on comment 3")
        #expect(reply.title(number: nil) == "Claude Code replied on a comment")
        #expect(reply.expires == Self.now.addingTimeInterval(5))
        #expect(reply.hint == nil)
        let question = Notice(subject: comment, kind: .question, agent: "Claude Code", text: "Which?", at: Self.now)
        #expect(question.title(number: 3) == "Claude Code asks about comment 3")
        #expect(question.expires == nil)
        #expect(Notice(subject: batch, kind: .message, agent: "Claude Code", text: "Done", at: Self.now).title(number: nil)
            == "Claude Code on the whole batch")
        #expect(Notice(subject: batch, kind: .acknowledgement, agent: "Claude Code", text: "On it", at: Self.now).expires
            == Self.now.addingTimeInterval(5))
    }

    @Test("every state the agent sets has its glyph on the pin, and an open question comes before an unread message")
    func pins() throws {
        #expect(CommentState.allCases.map(StateLook.pinGlyph) == [nil, nil, nil, "checkmark", "ellipsis", "checkmark", "xmark"])
    }
}
