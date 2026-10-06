import Darwin
import Foundation
@testable import ReviewApp
import ReviewCore
import ReviewLease
import ReviewWire
import Testing

/// The agent's answers on threads: the app's model on the fixture video and
/// the control server in front of it, asked as a listener and an operator
/// ask it. No window; the real socket for the last test only.
@Suite("Agent answers and questions on threads", .serialized)
struct AnswerTests {
    nonisolated static let operatorAgent = Holder(key: "operator", name: "Claude Code", place: "/work")
    nonisolated static let listener = Holder(key: "listener-1", name: "Mate", place: "/shop")

    let support = FileManager.default.temporaryDirectory
        .appendingPathComponent("havooch-tests-\(UUID().uuidString)", isDirectory: true)

    private func cleanUp() {
        try? FileManager.default.removeItem(at: support)
    }

    /// What a test works with: the model with the fixture open, the server
    /// in front of it, and a send of two messages on #1 and #2 that the
    /// listener took.
    private struct Taken {
        var model: AppModel
        var server: ControlServer
        var send: String
        /// The threads' ids.
        var one: String
        var two: String
        /// The messages' ids.
        var first: String
        var second: String
        var general: String
    }

    private func taken(socket: URL = URL(fileURLWithPath: "/nowhere/control.sock")) async throws -> Taken {
        let model = AppModel(environment: [SupportFolder.overrideVariable: support.path])
        try await model.open(MessageTests.fixture)
        let server = ControlServer(
            socket: socket, app: model, listeners: model.listeners, screenshotter: ControlServerTests.FakeScreenshotter(), quit: {}
        )
        let first = try await model.addMessage(text: "Too fast here", at: 10)
        let second = try await model.addMessage(text: "This box", at: 12.5, region: try Region(x: 0.25, y: 0.2, w: 0.3, h: 0.25))
        let send = try await model.sendQueue()
        let wait = await server.replyWritten(to: ControlRequest.wait(timeoutSeconds: 0).sent(by: Self.listener))
        #expect(wait.reply.ok)
        return Taken(
            model: model, server: server, send: send.id, one: first.thread.id, two: second.thread.id,
            first: first.message.id, second: second.message.id, general: try #require(model.desk.review?.general.id.text)
        )
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
        await app.server.replyWritten(to: request.sent(by: Self.listener, json: json)).reply
    }

    private func operate(_ request: ControlRequest, _ app: Taken, json: Bool = false) async -> ControlReply {
        await app.server.reply(to: request.sent(by: Self.operatorAgent, json: json)).reply
    }

    /// The thread `id` of the open video, as the model has it.
    private func thread(_ id: String, _ app: Taken) throws -> ReviewThread {
        try #require(app.model.threads.first { $0.id.text == id })
    }

    /// The person's messages' states, in the threads' order.
    private func states(_ app: Taken) -> [MessageState?] {
        app.model.threads.flatMap { $0.messages.filter(\.isWork).map(\.state) }
    }

    // MARK: - ack

    @Test("ack sets the messages of the send to acknowledged, and takes no lease")
    func ack() async throws {
        defer { cleanUp() }
        let app = try await taken()

        let reply = await listen(.ack(sendID: app.send, text: nil), app)

        #expect(reply == .done("\(app.send) acknowledged, 2 messages\n"))
        #expect(states(app) == [.acknowledged, .acknowledged])
        #expect(try thread(app.general, app).messages.isEmpty)
        #expect(app.server.lease.current(at: Date()) == nil)
        // The acknowledgement shows in the player, on General.
        #expect(app.model.notices.map(\.kind) == [.acknowledgement])
        #expect(app.model.notices.first?.title == "General · Mate")
        #expect(app.model.notices.first?.text == "It got your 2 messages.")
    }

    @Test("ack with text is the agent's message on General, in state and as a notice")
    func ackWithText() async throws {
        defer { cleanUp() }
        let app = try await taken()

        let reply = try object(await listen(.ack(sendID: app.send, text: "On it"), app, json: true).output)

        #expect((reply["send"] as? [String: Any])?["id"] as? String == app.send)
        let general = try thread(app.general, app)
        #expect(general.messages.map(\.text) == ["On it"])
        #expect(general.messages.first?.author == .agent)
        #expect(general.state == nil)
        #expect(app.model.notices.first?.text == "On it")
        #expect(app.model.notices.first?.thread.text == app.general)
    }

    @Test("an ack, a reply and a question keep the listener's name, so a later listener doesn't rename them")
    func sessionName() async throws {
        defer { cleanUp() }
        let app = try await taken()
        _ = await listen(.ack(sendID: app.send, text: "On it"), app)
        _ = await listen(.reply(thread: app.one, text: "Slowed it"), app)
        _ = await listen(.ask(thread: app.two, question: "Which box?", waitSeconds: 0), app)

        let agentMessages = app.model.threads.flatMap(\.messages).filter { $0.author == .agent }
        #expect(agentMessages.map(\.text) == ["On it", "Slowed it", "Which box?"])
        #expect(agentMessages.map(\.sessionName) == ["Mate", "Mate", "Mate"])
    }

    @Test("ack of an id that names no send is refused, and changes nothing")
    func ackUnknown() async throws {
        defer { cleanUp() }
        let app = try await taken()
        for id in ["s-00000000-1", app.first, "nonsense"] {
            let reply = await listen(.ack(sendID: id, text: "On it"), app)
            #expect(reply == .refused("no send `\(id)`; the send `havooch wait` printed names its id"))
        }
        let other = String(app.send.dropLast()) + "9"
        #expect(await listen(.ack(sendID: other, text: nil), app) == .refused(ReviewRefusal.unknownID(other).line))
        #expect(states(app) == [.sent, .sent])
        #expect(app.model.notices.isEmpty)
    }

    // MARK: - status

    @Test("each status shows on its message and thread, and the send's last finished message returns the listener to listening")
    func status() async throws {
        defer { cleanUp() }
        let app = try await taken()
        #expect(app.model.listeners.presence(at: Date()) == .working)

        #expect(await listen(.status(messageID: app.first, state: .working), app) == .done("\(app.first) working\n"))
        #expect(states(app) == [.working, .sent])
        #expect(try thread(app.one, app).state == .working)
        #expect(await listen(.status(messageID: app.first, state: .done), app) == .done("\(app.first) done\n"))
        #expect(app.model.listeners.outbox.taken.count == 1)

        let failed = try object(await listen(.status(messageID: app.second, state: .failed), app, json: true).output)
        #expect((failed["message"] as? [String: Any])?["state"] as? String == "failed")
        #expect((failed["message"] as? [String: Any])?["id"] as? String == app.second)
        #expect(try thread(app.two, app).state == .failed)

        // Nothing is left of the send: the listener isn't working any more.
        #expect(app.model.listeners.outbox.taken.isEmpty)
        let listening = app.server
        let wait = Task { await listening.replyWritten(to: ControlRequest.wait(timeoutSeconds: nil).sent(by: Self.listener)) }
        await eventually { app.model.listeners.outbox.isWaitOpen }
        #expect(app.model.listeners.presence(at: Date()) == .listening)
        app.server.stop()
        _ = await wait.value
    }

    @Test("status working with a text shows what the agent does now on its thread, the latest one, and done or failed clears it")
    func activity() async throws {
        defer { cleanUp() }
        let app = try await taken()
        let listeners = app.model.listeners
        let one = try thread(app.one, app).id, two = try thread(app.two, app).id
        func line(_ id: ThreadID) -> String? { listeners.activity(on: id, at: Date())?.text }

        #expect(await listen(.status(messageID: app.first, state: .working, text: "Reading the intro"), app).ok)
        #expect(await listen(.status(messageID: app.first, state: .working, text: "  Rendering 0:14 to 0:21\n"), app)
            == .done("\(app.first) working\n"))
        #expect(line(one) == "Rendering 0:14 to 0:21")
        #expect(line(two) == nil)
        #expect(await listen(.status(messageID: app.second, state: .working, text: "Cropping the box"), app).ok)

        // The newest first, as `state` reports it and the footer shows it.
        let state = try object(await operate(.state, app, json: true).output)
        let activity = try #require((state["listener"] as? [String: Any])?["activity"] as? [[String: Any]])
        #expect(activity.map { $0["text"] as? String } == ["Cropping the box", "Rendering 0:14 to 0:21"])
        #expect(activity.map { $0["thread"] as? String } == [app.two, app.one])
        #expect(activity.map { $0["message"] as? String } == [app.second, app.first])
        #expect(await operate(.state, app).output.contains("  now on \(app.two): Cropping the box\n"))

        // A status with no text keeps the line; done and failed clear it.
        #expect(await listen(.status(messageID: app.first, state: .working), app).ok)
        #expect(line(one) == "Rendering 0:14 to 0:21")
        #expect(await listen(.status(messageID: app.first, state: .done), app).ok)
        #expect(line(one) == nil)
        #expect(line(two) == "Cropping the box")
        #expect(await listen(.status(messageID: app.second, state: .failed), app).ok)
        #expect(listeners.activities(at: Date()).isEmpty)
        #expect(listeners.report(at: Date()).activity.isEmpty)
    }

    @Test("an empty text clears the line, a new listener session clears every line, and no line shows while no agent is there")
    func activityCleared() async throws {
        defer { cleanUp() }
        let app = try await taken()
        let listeners = app.model.listeners
        let one = try thread(app.one, app).id
        #expect(await listen(.status(messageID: app.first, state: .working, text: "Reading"), app).ok)
        #expect(await listen(.status(messageID: app.first, state: .working, text: " "), app).ok)
        #expect(listeners.activity(on: one, at: Date()) == nil)

        #expect(await listen(.status(messageID: app.second, state: .working, text: "Cropping"), app).ok)
        // The agent went quiet: past the grace, nothing it said still shows.
        let later = Date().addingTimeInterval(Outbox.workingGrace + 1)
        #expect(listeners.activities(at: later).isEmpty)
        #expect(listeners.activity(on: try thread(app.two, app).id, at: later) == nil)

        // Another listener takes the unfinished send over: its work starts again.
        let other = Holder(key: "listener-2", name: "Mate", place: "/shop")
        #expect(await app.server.replyWritten(to: ControlRequest.wait(timeoutSeconds: 0).sent(by: other)).reply.ok)
        #expect(listeners.activities(at: Date()).isEmpty)
    }

    @Test("a status that moves a message back, or names no message, is refused")
    func statusRefused() async throws {
        defer { cleanUp() }
        let app = try await taken()
        _ = await listen(.status(messageID: app.first, state: .done), app)

        let back = await listen(.status(messageID: app.first, state: .working), app)
        #expect(back == .refused(
            "\(app.first) is done and can't move to working: a message only moves forward (sent, acknowledged, working, then done or failed)"
        ))
        #expect(await listen(.status(messageID: app.first, state: .failed), app).ok == false)
        // Saying it again changes nothing.
        #expect(await listen(.status(messageID: app.first, state: .done), app).ok)
        for id in ["m-00000000-1", app.send, "nonsense"] {
            #expect(await listen(.status(messageID: id, state: .done), app)
                == .refused("no message `\(id)`; the send `havooch wait` printed names each message's id"))
        }
        #expect(states(app) == [.done, .sent])
    }

    // MARK: - reply

    @Test("reply shows on its thread and as a notice that names it, and marks the thread until the person looks")
    func reply() async throws {
        defer { cleanUp() }
        let app = try await taken()
        let two = try #require(ItemID(app.two))
        #expect(app.model.selection == two)

        let reply = await listen(.reply(thread: app.one, text: "Slowed the intro down"), app)

        let message = try #require(try thread(app.one, app).messages.last)
        #expect(reply == .done("\(message.id) on #1\n"))
        #expect(message.author == .agent)
        #expect(message.kind == .message)
        #expect(message.text == "Slowed the intro down")
        #expect(try thread(app.two, app).messages.count == 1)
        // The thread's state is still its person message's.
        #expect(try thread(app.one, app).state == .sent)

        let notice = try #require(app.model.notices.first)
        #expect(notice.thread.text == app.one)
        #expect(notice.kind == .message)
        #expect(notice.title == "#1 · Mate")

        // A click on the notice: it goes, and the thread's popover opens on its frame.
        app.model.openNotice(notice.id)
        #expect(app.model.notices.isEmpty)
        #expect(app.model.selection == ItemID(app.one))
        #expect(app.model.state().popover?.thread == 1)
    }

    @Test("a reply on General, by its number, is a message about the whole send")
    func replyOnGeneral() async throws {
        defer { cleanUp() }
        let app = try await taken()

        let reply = try object(await listen(.reply(thread: "0", text: "Both fixed in one commit"), app, json: true).output)

        let message = try #require(reply["message"] as? [String: Any])
        #expect(message["author"] as? String == "agent")
        #expect(message["kind"] as? String == "message")
        #expect(try thread(app.general, app).messages.map(\.text) == ["Both fixed in one commit"])
        #expect(app.model.notices.first?.title == "General · Mate")

        // General has no frame: a click on its notice shows its thread view.
        let notice = try #require(app.model.notices.first)
        app.model.openNotice(notice.id)
        #expect(app.model.shown == ItemID(app.general))
        #expect(app.model.state().sidebar?.thread == app.general)
        #expect(app.model.state().popover == nil)
    }

    @Test("a reply on a thread that names nothing, has nothing sent, or has no words, is refused")
    func replyRefused() async throws {
        defer { cleanUp() }
        let app = try await taken()
        for id in ["m-00000000-1", "nonsense"] {
            #expect(await listen(.reply(thread: id, text: "Hello"), app)
                == .refused("no thread `\(id)`; give a thread id from the send `havooch wait` printed, or a number of the open video"))
        }
        #expect(await listen(.reply(thread: "7", text: "Hello"), app).ok == false)
        let unsent = try await app.model.addMessage(text: "Not sent yet", at: 15)
        #expect(await listen(.reply(thread: unsent.thread.id, text: "Hello"), app)
            == .refused(ReviewRefusal.notSent(try #require(ItemID(unsent.thread.id))).line))
        #expect(await listen(.reply(thread: app.one, text: "  "), app) == .refused("a message needs text"))
        #expect(app.model.notices.isEmpty)
    }

    @Test("a notice goes by itself, a question's too")
    func noticesGo() async throws {
        defer { cleanUp() }
        let app = try await taken()
        _ = await listen(.reply(thread: app.one, text: "Done"), app)
        _ = await listen(.ask(thread: app.two, question: "Which box?", waitSeconds: 0), app)
        #expect(app.model.notices.map(\.kind) == [.message, .question])
        #expect(app.model.notices[1].expires.timeIntervalSinceNow <= Notice.life)
        #expect(app.model.notices[1].hint == "Click to answer")
        let message = app.model.notices[0]
        #expect(message.expires.timeIntervalSinceNow <= Notice.life)

        app.model.dismiss(message.id)
        #expect(app.model.notices.map(\.kind) == [.question])
    }

    // MARK: - ask and answer

    @Test("ask --wait exits with the answer that thread answer gives, and the thread keeps each message's author and kind")
    func askAnsweredByTheOperator() async throws {
        defer { cleanUp() }
        let app = try await taken()
        let server = app.server
        let two = app.two
        let asking = Task { await server.reply(to: ControlRequest.ask(thread: two, question: "Which box?", waitSeconds: 30).sent(by: Self.listener)) }
        await eventually { app.model.listeners.outbox.openAsks == 1 }
        #expect(try thread(app.two, app).openQuestion?.text == "Which box?")
        #expect(ThreadSummary(try thread(app.two, app), agent: "Mate").waitsForAnswer)
        #expect(app.model.notices.first?.title == "#2 · Mate")

        let answered = await operate(.threadAnswer(thread: "2", text: "The left one"), app)
        let reply = await asking.value.reply

        #expect(answered == .done("#2 answered\n"))
        #expect(reply == .done("The left one\n"))
        #expect(app.model.listeners.outbox.openAsks == 0)
        #expect(try thread(app.two, app).openQuestion == nil)
        // The question's notice goes with its answer.
        #expect(app.model.notices.isEmpty)
        let messages = try thread(app.two, app).messages
        #expect(messages.map(\.author) == [.person, .agent, .person])
        #expect(messages.map(\.kind) == [.message, .question, .answer])
        // An answer is never queued.
        #expect(app.model.state().queue.isEmpty)
        #expect(app.server.lease.current(at: Date())?.holder.key == "operator")
    }

    @Test("ask --wait exits with the answer the person gives in the answer field, as JSON with --json")
    func askAnsweredByThePerson() async throws {
        defer { cleanUp() }
        let app = try await taken()
        let server = app.server
        let one = app.one
        let asking = Task {
            await server.reply(to: ControlRequest.ask(thread: one, question: "Which part?", waitSeconds: nil).sent(by: Self.listener, json: true))
        }
        await eventually { app.model.listeners.outbox.openAsks == 1 }

        #expect(app.model.answerQuestion(try #require(ItemID(app.one)), text: " The intro "))

        let answer = try #require(try object(await asking.value.reply.output)["answer"] as? [String: Any])
        #expect(answer["text"] as? String == "The intro")
        #expect(answer["author"] as? String == "person")
        #expect(answer["kind"] as? String == "answer")
        #expect(app.model.problem == nil)
        #expect(app.server.lease.current(at: Date()) == nil)
    }

    @Test("an ask with choices keeps them on its question, which state --json lists, and thread choose answers with one at once")
    func askWithChoicesAnsweredByChoose() async throws {
        defer { cleanUp() }
        let app = try await taken()
        let server = app.server
        let two = app.two
        let asking = Task {
            await server.reply(
                to: ControlRequest.ask(thread: two, question: "Which box?", waitSeconds: 30, choices: ["The left one", "The right one"])
                    .sent(by: Self.listener)
            )
        }
        await eventually { app.model.listeners.outbox.openAsks == 1 }
        #expect(try thread(app.two, app).openQuestion?.choices == ["The left one", "The right one"])
        let state = try object(await operate(.state, app, json: true).output)
        let threads = try #require(state["threads"] as? [[String: Any]])
        let messages = try #require(threads.first { $0["id"] as? String == two }?["messages"] as? [[String: Any]])
        #expect(messages.last?["choices"] as? [String] == ["The left one", "The right one"])
        // Only a question with choices names them.
        #expect(messages.first?["choices"] == nil)

        #expect(await operate(.threadChoose(thread: "2", choice: 3), app) == .refused(ReviewRefusal.noChoice(try #require(ItemID(two)), 3).line))
        let chosen = await operate(.threadChoose(thread: "2", choice: 2), app)
        let reply = await asking.value.reply

        #expect(chosen == .done("#2 answered: The right one\n"))
        #expect(reply == .done("The right one\n"))
        #expect(try thread(app.two, app).openQuestion == nil)
        #expect(try thread(app.two, app).messages.last?.kind == .answer)
        #expect(app.model.state().queue.isEmpty)
    }

    @Test("a click on a quick reply answers the open question at once, and one on a question no longer open is refused in words")
    func quickReplyClick() async throws {
        defer { cleanUp() }
        let app = try await taken()
        let one = try #require(ItemID(app.one))
        _ = await listen(.ask(thread: app.one, question: "Which part?", waitSeconds: 0, choices: ["The intro", "The end"]), app)

        #expect(app.model.chooseAnswer(one, choice: 1))
        #expect(try thread(app.one, app).messages.last?.text == "The intro")
        #expect(app.model.problem == nil)

        #expect(!app.model.chooseAnswer(one, choice: 1))
        #expect(app.model.problem?.reason == ReviewRefusal.noQuestion(one).line)
    }

    @Test("the person points at a region while drawing a rectangle, and stops when it's cancelled")
    func pointingAtRegion() async throws {
        defer { cleanUp() }
        let app = try await taken()
        #expect(!app.model.isPointingAtRegion)
        app.model.beginRegion()
        #expect(app.model.isPointingAtRegion)
        app.model.endRegion(nil)
        #expect(!app.model.isPointingAtRegion)
    }

    @Test("an ask whose wait runs out answers that it ran out; the question stays open, and a late answer stays on the thread")
    func askRunsOut() async throws {
        defer { cleanUp() }
        let app = try await taken()
        let started = Date()

        let reply = await listen(.ask(thread: app.one, question: "Which part?", waitSeconds: 1), app)

        #expect(reply == .ranOut)
        #expect(Date().timeIntervalSince(started) >= 1)
        #expect(app.model.listeners.outbox.openAsks == 0)
        #expect(try thread(app.one, app).openQuestion != nil)

        #expect(await operate(.threadAnswer(thread: app.one, text: "The intro"), app).ok)
        #expect(try thread(app.one, app).messages.map(\.kind) == [.message, .question, .answer])
        #expect(app.model.notices.isEmpty)
    }

    @Test("a second question while one is open, and an answer with no question, are refused")
    func askAndAnswerRefused() async throws {
        defer { cleanUp() }
        let app = try await taken()
        let one = try #require(ItemID(app.one))
        #expect(await operate(.threadAnswer(thread: app.one, text: "Yes"), app) == .refused(ReviewRefusal.noQuestion(one).line))
        #expect(await listen(.ask(thread: app.one, question: "Which part?", waitSeconds: 0), app) == .ranOut)

        let second = await listen(.ask(thread: app.one, question: "And how?", waitSeconds: 30), app)
        #expect(second == .refused(ReviewRefusal.questionOpen(one).line))
        #expect(try thread(app.one, app).messages.count == 2)
        #expect(app.model.listeners.outbox.openAsks == 0)
        #expect(await operate(.threadAnswer(thread: "t-00000000-1", text: "Yes"), app).ok == false)
        #expect(await operate(.threadAnswer(thread: app.one, text: " "), app) == .refused("a message needs text"))

        // The answer field says why it didn't take an answer.
        #expect(!app.model.answerQuestion(try #require(ItemID(app.two)), text: "Yes"))
        #expect(app.model.problem?.title == "The answer wasn't sent")
    }

    @Test("when the app quits, an open ask ends with no reply, and its question stays on the thread")
    func quitting() async throws {
        defer { cleanUp() }
        let app = try await taken()
        let server = app.server
        let one = app.one
        let asking = Task { await server.reply(to: ControlRequest.ask(thread: one, question: "Which part?", waitSeconds: nil).sent(by: Self.listener)) }
        await eventually { app.model.listeners.outbox.openAsks == 1 }

        app.server.stop()

        #expect(await asking.value.silent)
        #expect(app.model.listeners.outbox.openAsks == 0)
        #expect(try thread(app.one, app).openQuestion != nil)
    }

    @Test("the state lines list each thread with its messages")
    func stateLines() async throws {
        defer { cleanUp() }
        let app = try await taken()
        _ = await listen(.reply(thread: app.one, text: "Looking"), app)
        let lines = await listen(.state, app).output
        #expect(lines.contains("threads: 3 (0 queued)\n"))
        #expect(lines.contains("  #1 at 0:10 \(app.one) sent unread\n"))
        #expect(lines.contains("    \(app.first) person message sent: Too fast here\n"))
        #expect(lines.contains(" agent message: Looking\n"))
        #expect(lines.contains(" region 0.25,0.2,0.3,0.25: This box\n"))
    }

    @Test("the listener answers on a thread of a video that's no longer the open one: its ids name their video")
    func anotherVideoOpen() async throws {
        defer { cleanUp() }
        let app = try await taken()
        // The same film with other content: another video to the app.
        let other = support.appendingPathComponent("other.mp4")
        var bytes = try Data(contentsOf: MessageTests.fixture)
        bytes.append(Data(repeating: 0, count: 16))
        try bytes.write(to: other)
        let first = try #require(app.model.video?.contentHash)
        try await app.model.open(other)
        #expect(app.model.video?.contentHash != first)
        #expect(app.model.state().threads.map(\.number) == [0])

        #expect(await listen(.ack(sendID: app.send, text: "On it"), app).ok)
        #expect(await listen(.reply(thread: app.one, text: "Done"), app).ok)
        let status = try object(await listen(.status(messageID: app.first, state: .done), app, json: true).output)
        _ = await listen(.ask(thread: app.two, question: "Which box?", waitSeconds: 0), app)
        #expect(await operate(.threadAnswer(thread: app.two, text: "The left one"), app).ok)
        // A bare number names the open video's thread, which has none.
        #expect(await listen(.reply(thread: "1", text: "Done"), app).ok == false)

        #expect((status["message"] as? [String: Any])?["state"] as? String == "done")
        let review = try #require(app.model.desk.review(of: first))
        #expect(review.threads.flatMap { $0.messages.filter(\.isWork).map(\.state) } == [.done, .acknowledged])
        #expect(review.threads.map(\.messages.count) == [1, 2, 3])
        // The open video's review is untouched.
        #expect(app.model.state().threads.map(\.messages.count) == [0])
    }

    // MARK: - Over the socket

    @Test("over the real socket, an ask is held until thread answer, and an ask whose client goes away stops waiting")
    func overTheSocket() async throws {
        defer { cleanUp() }
        let folder = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("havooch-\(UUID().uuidString.prefix(8))", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let app = try await taken(socket: ControlSocket.url(in: folder))
        try app.server.start()
        defer { app.server.stop() }
        let socket = app.server.socket
        let one = app.one

        async let asked = LeaseServerTests.sending {
            ControlClient(socket: socket, holder: Self.listener, transport: UnixSocketTransport())
                .send(.ask(thread: one, question: "Which part?", waitSeconds: 30))
        }
        await eventually { app.model.listeners.outbox.openAsks == 1 }
        let answered = await LeaseServerTests.sending {
            ControlClient(socket: socket, holder: Self.operatorAgent, transport: UnixSocketTransport())
                .send(.threadAnswer(thread: one, text: "The intro"))
        }
        #expect(try answered.get().ok)
        #expect(try await asked.get() == .done("The intro\n"))

        // An `ask` that's stopped: it sent its request, then its process ended.
        let descriptor = UnixSocket.make()
        let address = try #require(UnixSocket.address(socket.path))
        #expect(UnixSocket.connectSocket(descriptor, to: address) == 0)
        #expect(UnixSocket.writeAll(descriptor, ControlRequest.ask(thread: app.two, question: "Which box?", waitSeconds: nil).sent(by: Self.listener)))
        UnixSocket.finishWriting(descriptor)
        await eventually { app.model.listeners.outbox.openAsks == 1 }
        #expect(app.model.listeners.outbox.openAsks == 1)
        close(descriptor)
        await eventually { app.model.listeners.outbox.openAsks == 0 }
        #expect(app.model.listeners.outbox.openAsks == 0)
        #expect(try thread(app.two, app).openQuestion?.text == "Which box?")
    }
}

@Suite("The thread's words")
struct ThreadWordsTests {
    static let now = Date(timeIntervalSince1970: 1_790_000_000)

    @Test("a notice names its thread, or General, and every notice fades after five seconds")
    func notices() {
        let reply = Notice(thread: ItemID("t-f92cbb2a-3")!, kind: .message, agent: "Claude Code", text: "Done", at: Self.now)
        #expect(reply.title == "#3 · Claude Code")
        #expect(reply.expires == Self.now.addingTimeInterval(5))
        #expect(reply.hint == nil)
        let question = Notice(thread: ItemID("t-f92cbb2a-3")!, kind: .question, agent: "Claude Code", text: "Which?", at: Self.now)
        #expect(question.expires == Self.now.addingTimeInterval(5))
        let ack = Notice(thread: ItemID("t-f92cbb2a-0")!, kind: .acknowledgement, agent: "Claude Code", text: "On it", at: Self.now)
        #expect(ack.title == "General · Claude Code")
        #expect(ack.expires == Self.now.addingTimeInterval(5))
    }

    @Test("every state the agent sets has its glyph on the pin")
    func pins() throws {
        #expect(MessageState.allCases.map(StateLook.pinGlyph) == [nil, nil, "checkmark", "ellipsis", "checkmark", "xmark"])
    }
}
