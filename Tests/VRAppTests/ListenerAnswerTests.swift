import Darwin
import Foundation
import Testing
@testable import VRApp
import VRLease
import VRReview
import VRWire

/// The listener's answers, from `ack` to the person's answer reaching an
/// `ask`: requests answered in memory at times the test sets, and over the
/// real socket in a temporary folder, on the fixture video. No window is
/// opened and no sound is made.
@Suite(.serialized) @MainActor struct ListenerAnswerTests {
    typealias Wait = ListenerWaitTests

    let clock = Wait.Clock()
    let folder = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("vr-\(UUID().uuidString.prefix(8))", isDirectory: true)
    var socket: URL { folder.appendingPathComponent("control.sock") }

    /// The app with the fixture open, `c1` at 10 s and `c2` (on a region)
    /// at 4 s sent as `b1`, and the batch taken by the listener `L1`.
    struct Scene {
        var model: AppModel
        var server: ControlServer
        var c1: String
        var c2: String
        var b1: String
    }

    func scene(taken: Bool = true, heartbeat: Duration = .milliseconds(40)) async throws -> Scene {
        let model = AppModel(environment: [SupportFolder.overrideVariable: folder.path], now: { [clock] in clock.now })
        model.player.player.isMuted = true
        try await model.open(RegionCommentTests.fixture)
        let server = ControlServer(
            socket: socket, model: model, screenshotter: Screenshotter(model: model), lease: ControlLease(), indicator: LeaseIndicator(),
            now: { [clock] in clock.now }, timeZone: TimeZone(identifier: "UTC") ?? .gmt, heartbeat: heartbeat, quit: {}
        )
        _ = await server.reply(to: Wait.sent(.commentAdd(text: "too fast", at: 10, region: nil)))
        _ = await server.reply(to: Wait.sent(.commentAdd(text: "this box", at: 4, region: WireRegion(x: 0.1, y: 0.2, w: 0.3, h: 0.2))))
        _ = await server.reply(to: Wait.sent(.batchSend))
        if taken {
            server.written(await server.reply(to: Wait.sent(.wait(timeoutSeconds: nil), by: Wait.first)))
        }
        let prefix = try #require(model.desk.open).video.contentHash.prefix(8)
        return Scene(model: model, server: server, c1: "\(prefix)-c1", c2: "\(prefix)-c2", b1: "\(prefix)-b1")
    }

    /// A listener's request, from `L1`.
    func listener(_ request: ControlRequest, on scene: Scene, json: Bool = false) async -> ControlServer.Answer {
        await scene.server.reply(to: Wait.sent(request, by: Wait.first, json: json))
    }

    /// An operator's request.
    func driver(_ request: ControlRequest, on scene: Scene, json: Bool = false) async -> ControlServer.Answer {
        await scene.server.reply(to: Wait.sent(request, json: json))
    }

    func state(of scene: Scene) async throws -> [String: Any] {
        let reply = await scene.server.reply(to: Wait.sent(.state, by: Wait.second))
        return try #require(JSONSerialization.jsonObject(with: Data(reply.reply.output.utf8)) as? [String: Any])
    }

    /// The comment `id` as `state` lists it.
    func comment(_ id: String, of scene: Scene) async throws -> [String: Any] {
        let comments = try #require(try await state(of: scene)["comments"] as? [[String: Any]])
        return try #require(comments.first { $0["id"] as? String == id })
    }

    func states(of scene: Scene) async throws -> [String: String] {
        let comments = try #require(try await state(of: scene)["comments"] as? [[String: Any]])
        return Dictionary(uniqueKeysWithValues: comments.compactMap { comment in
            (comment["id"] as? String).flatMap { id in (comment["state"] as? String).map { (id, $0) } }
        })
    }

    static func object(_ answer: ControlServer.Answer) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: Data(answer.reply.output.utf8)) as? [String: Any])
    }

    /// Waits until the question on `id` shows as waiting.
    func untilAsked(_ id: CommentID, on scene: Scene) async throws {
        for _ in 0..<500 {
            if (try? scene.model.desk.open?.comment(id))?.openQuestion != nil { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("the question never arrived")
    }

    func until(_ wanted: String, on scene: Scene) async throws {
        for _ in 0..<500 {
            if (try await state(of: scene)["listener"] as? [String: Any])?["presence"] as? String == wanted { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("the listener never became \(wanted)")
    }

    // MARK: - Acknowledging and statuses

    @Test func ackSetsTheCommentsOfTheBatchToAcknowledgedAndItsTextIsAMessageForTheBatch() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let scene = try await scene()

        let plain = await listener(.ack(id: scene.b1, text: nil), on: scene)
        let quiet = try await state(of: scene)
        clock.now += 5
        let said = await listener(.ack(id: scene.b1, text: "got it"), on: scene, json: true)

        #expect(plain == .init(reply: .done("acknowledged \(scene.b1)\n")))
        #expect(said == .init(reply: .done(#"{"batchId":"\#(scene.b1)","commentIds":["\#(scene.c2)","\#(scene.c1)"]}"# + "\n")))
        #expect(try await states(of: scene) == [scene.c1: "acknowledged", scene.c2: "acknowledged"])
        // An acknowledgement that says nothing announces nothing.
        #expect(quiet["notice"] is NSNull)
        let state = try await state(of: scene)
        let batch = try #require((state["batches"] as? [[String: Any]])?.first)
        let thread = try #require(batch["thread"] as? [[String: String]])
        #expect(thread == [["author": "agent", "kind": "message", "text": "got it", "at": "2026-10-04T12:00:05Z"]])
        #expect(batch["delivery"] as? String == "taken")
        let notice = try #require(state["notice"] as? [String: Any])
        #expect(notice["batchId"] as? String == scene.b1)
        #expect(notice["commentId"] is NSNull)
        #expect(notice["kind"] as? String == "message")
        #expect(notice["text"] as? String == "got it")
    }

    @Test func aStatusShowsOnItsCommentAndOnlyMovesForward() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let scene = try await scene()
        _ = await listener(.ack(id: scene.b1, text: nil), on: scene)

        let working = await listener(.status(id: scene.c1, state: "working"), on: scene)
        let shown = try await states(of: scene)
        let done = await listener(.status(id: scene.c1, state: "done"), on: scene, json: true)
        let back = await listener(.status(id: scene.c1, state: "working"), on: scene)
        let skipped = await listener(.status(id: scene.c2, state: "failed"), on: scene)

        #expect(working == .init(reply: .done("\(scene.c1) working\n")))
        #expect(shown == [scene.c1: "working", scene.c2: "acknowledged"])
        #expect(try Self.object(done)["state"] as? String == "done")
        #expect(try Self.object(done)["id"] as? String == scene.c1)
        #expect(back == .init(reply: .refused(
            "\(scene.c1) is done and can't become working; a comment only moves forward: "
                + "sent, acknowledged, working, then done or failed, which are final"
        )))
        #expect(skipped == .init(reply: .done("\(scene.c2) failed\n")))
        #expect(try await states(of: scene) == [scene.c1: "done", scene.c2: "failed"])
    }

    @Test func aStatusThatIsNotOneAndAnIdThatNamesNothingAreRefusedInWords() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let scene = try await scene()

        #expect(await listener(.status(id: scene.c1, state: "sent"), on: scene)
            == .init(reply: .refused("no status `sent`; it takes `working`, `done` or `failed`")))
        #expect(await listener(.status(id: "0badf00d-c1", state: "done"), on: scene) == .init(reply: .refused("there is no comment `0badf00d-c1`")))
        #expect(await listener(.status(id: String(scene.c1.dropLast()) + "9", state: "done"), on: scene)
            == .init(reply: .refused("there is no comment `\(String(scene.c1.dropLast()))9`")))
        #expect(await listener(.ack(id: "0badf00d-b1", text: nil), on: scene) == .init(reply: .refused("there is no batch `0badf00d-b1`")))
        #expect(await listener(.reply(id: "nonsense", text: "hello"), on: scene) == .init(reply: .refused("there is no comment `nonsense`")))
        #expect(await listener(.reply(id: scene.c1, text: "  "), on: scene) == .init(reply: .refused("a message needs some text")))
        #expect(try await states(of: scene) == [scene.c1: "sent", scene.c2: "sent"])
    }

    @Test func theStatusThatFinishesABatchTellsTheLedgerAndTheListenerHasNothingLeft() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let scene = try await scene()
        #expect(scene.model.listener.ledger.deliveries.map(\.batch.rawValue) == [scene.b1])

        _ = await listener(.status(id: scene.c1, state: "done"), on: scene)
        let half = scene.model.listener.standing(of: BatchID(rawValue: scene.b1))
        _ = await listener(.status(id: scene.c2, state: "failed"), on: scene)

        #expect(half == .taken)
        #expect(scene.model.listener.ledger.deliveries.isEmpty)
        let state = try await state(of: scene)
        #expect((state["batches"] as? [[String: Any]])?.first?["delivery"] as? String == "finished")
        // No batch is left with the listener, and no wait is open.
        #expect((state["listener"] as? [String: Any])?["presence"] as? String == "absent")
        // A new listener gets nothing of it again.
        #expect(await scene.server.reply(to: Wait.sent(.wait(timeoutSeconds: 0), by: Wait.second)) == .init(reply: .done("")))
    }

    @Test func aListenersCommandFindsItsCommentWhateverVideoIsOpen() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let scene = try await scene()
        // The person closed the video: no review is the open one.
        scene.model.desk.close()

        let working = await listener(.status(id: scene.c1, state: "working"), on: scene)
        let replied = await listener(.reply(id: scene.c1, text: "on it"), on: scene)

        #expect(working == .init(reply: .done("\(scene.c1) working\n")))
        #expect(replied == .init(reply: .done("replied \(scene.c1)\n")))
        let hash = try #require(scene.model.desk.hash(naming: scene.c1))
        #expect(try scene.model.desk.review(hash)?.comment(CommentID(rawValue: scene.c1)).thread.map(\.text) == ["on it"])
    }

    @Test func anAnswerFromANewListenerPutsTheOldOnesBatchBackForIt() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let scene = try await scene()
        _ = await listener(.ack(id: scene.b1, text: nil), on: scene)

        // Another key is the listener restarted: what the one before made of the batch is undone.
        _ = await scene.server.reply(to: Wait.sent(.reply(id: scene.b1, text: "I'm new here"), by: Wait.second))

        #expect(scene.model.listener.session?.key == "L2")
        #expect(scene.model.listener.standing(of: BatchID(rawValue: scene.b1)) == .pending)
        #expect(try await states(of: scene) == [scene.c1: "sent", scene.c2: "sent"])
    }

    // MARK: - Replies

    @Test func aReplyShowsInTheThreadOfItsCommentAndAsANotice() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let scene = try await scene()

        let replied = await listener(.reply(id: scene.c1, text: "slowed scene two by half a second"), on: scene)
        clock.now += 60
        let again = await listener(.reply(id: scene.c1, text: "done in a1b2c3"), on: scene, json: true)

        #expect(replied == .init(reply: .done("replied \(scene.c1)\n")))
        let printed = try #require(try Self.object(again)["thread"] as? [[String: String]])
        let thread = try #require(try await comment(scene.c1, of: scene)["thread"] as? [[String: String]])
        #expect(thread == [
            ["author": "agent", "kind": "message", "text": "slowed scene two by half a second", "at": "2026-10-04T12:00:00Z"],
            ["author": "agent", "kind": "message", "text": "done in a1b2c3", "at": "2026-10-04T12:01:00Z"],
        ])
        #expect(printed == thread)
        #expect(try await comment(scene.c2, of: scene)["thread"] as? [[String: String]] == [])
        // The notice is the last message, on its comment.
        let notice = try #require(try await state(of: scene)["notice"] as? [String: Any])
        #expect(notice["commentId"] as? String == scene.c1)
        #expect(notice["batchId"] as? String == scene.b1)
        #expect(notice["kind"] as? String == "message")
        #expect(notice["text"] as? String == "done in a1b2c3")
        #expect(scene.model.notice?.title == "Agent · 0:10")
    }

    @Test func aReplyToABatchIdShowsAsAMessageForTheWholeBatch() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let scene = try await scene()

        let replied = await listener(.reply(id: scene.b1, text: "both are in a1b2c3"), on: scene)
        let json = await listener(.reply(id: scene.b1, text: "and pushed"), on: scene, json: true)

        #expect(replied == .init(reply: .done("replied \(scene.b1)\n")))
        #expect(json == .init(reply: .done(#"{"batchId":"\#(scene.b1)"}"# + "\n")))
        let state = try await state(of: scene)
        let batch = try #require((state["batches"] as? [[String: Any]])?.first)
        #expect((batch["thread"] as? [[String: String]])?.map { $0["text"] } == ["both are in a1b2c3", "and pushed"])
        #expect((batch["thread"] as? [[String: String]])?.map { $0["kind"] } == ["message", "message"])
        // No comment's thread got it.
        #expect(try await comment(scene.c1, of: scene)["thread"] as? [[String: String]] == [])
        let notice = try #require(state["notice"] as? [String: Any])
        #expect(notice["commentId"] is NSNull)
        #expect(scene.model.notice?.title == "Agent · Batch 1")
    }

    @Test func aClickOnTheNoticeGoesToItsCommentAndTakesItDown() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let scene = try await scene()
        _ = await listener(.reply(id: scene.c2, text: "which box?"), on: scene)
        #expect(scene.model.notice != nil)

        scene.model.openNotice()

        #expect(scene.model.notice == nil)
        #expect(scene.model.selection?.rawValue == scene.c2)
        #expect(try await state(of: scene)["notice"] is NSNull)
    }

    // MARK: - Questions

    @Test func askExitsWithTheAnswerThatThreadAnswerGives() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let scene = try await scene()

        let asking = Task { await listener(.ask(id: scene.c2, text: "Which box, left or right?", waitSeconds: 60), on: scene) }
        try await untilAsked(CommentID(rawValue: scene.c2), on: scene)
        let notice = scene.model.notice
        // The main actor is free while the ask is open: the operator's answer is taken.
        clock.now += 7
        let answered = await driver(.threadAnswer(id: scene.c2, text: "The left one"), on: scene)
        let answer = await asking.value

        #expect(answer == .init(reply: .done("The left one\n")))
        #expect(answered == .init(reply: .done("answered \(scene.c2)\n")))
        #expect(notice?.kind == .question)
        #expect(notice?.title == "Agent asks · 0:04")
        let thread = try #require(try await comment(scene.c2, of: scene)["thread"] as? [[String: String]])
        #expect(thread == [
            ["author": "agent", "kind": "question", "text": "Which box, left or right?", "at": "2026-10-04T12:00:00Z"],
            ["author": "person", "kind": "answer", "text": "The left one", "at": "2026-10-04T12:00:07Z"],
        ])
    }

    @Test func askExitsWithTheAnswerThePersonGivesInTheAnswerBox() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let scene = try await scene()

        let asking = Task { await listener(.ask(id: scene.c1, text: "Slower by how much?", waitSeconds: nil), on: scene, json: true) }
        try await untilAsked(CommentID(rawValue: scene.c1), on: scene)
        // What Return in the answer box calls: no lease is asked of the person.
        let taken = scene.model.answerForPerson(CommentID(rawValue: scene.c1), text: " Half a second ")
        let answer = await asking.value

        #expect(taken)
        #expect(answer == .init(reply: .done(#"{"answer":"Half a second","commentId":"\#(scene.c1)"}"# + "\n")))
        // A second answer has no question to answer: the person is told.
        #expect(!scene.model.answerForPerson(CommentID(rawValue: scene.c1), text: "or a whole one"))
        #expect(scene.model.failure == "\(scene.c1) has no question waiting for an answer")
    }

    @Test func anAskThatRunsOutLeavesItsQuestionOpenAndTheSameAskAgainGetsTheAnswerAtOnce() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let scene = try await scene()

        let ranOut = await listener(.ask(id: scene.c1, text: "Slower by how much?", waitSeconds: 0), on: scene)
        let open = try #require(scene.model.desk.open).comments.first { $0.id.rawValue == scene.c1 }?.openQuestion?.text
        // The person answers while nobody waits.
        _ = await driver(.threadAnswer(id: scene.c1, text: "Half a second"), on: scene)
        let again = await listener(.ask(id: scene.c1, text: "Slower by how much?", waitSeconds: 0), on: scene)

        // What the command turns into exit 3.
        #expect(ranOut == .init(reply: .done("")))
        #expect(open == "Slower by how much?")
        #expect(again == .init(reply: .done("Half a second\n")))
        // The question was posted once.
        let thread = try #require(try await comment(scene.c1, of: scene)["thread"] as? [[String: String]])
        #expect(thread.map { $0["kind"] } == ["question", "answer"])
    }

    @Test func anAskWhoseWaitRunsOutWhileItIsOpenAnswersWithNothing() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let scene = try await scene()

        let ranOut = await listener(.ask(id: scene.c1, text: "Slower by how much?", waitSeconds: 1), on: scene)

        #expect(ranOut == .init(reply: .done("")))
        #expect(try #require(scene.model.desk.open).comments.first { $0.id.rawValue == scene.c1 }?.openQuestion != nil)
    }

    @Test func theSameAskWhileOneIsOpenAttachesToItAndBothGetTheAnswer() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let scene = try await scene()

        let first = Task { await listener(.ask(id: scene.c1, text: "Slower by how much?", waitSeconds: nil), on: scene) }
        try await untilAsked(CommentID(rawValue: scene.c1), on: scene)
        let second = Task { await listener(.ask(id: scene.c1, text: "Slower by how much?", waitSeconds: nil), on: scene) }
        // Let the second ask reach its wait.
        for _ in 0..<20 { await Task.yield() }
        try await Task.sleep(for: .milliseconds(50))
        _ = await driver(.threadAnswer(id: scene.c1, text: "Half a second"), on: scene)

        #expect(await first.value == .init(reply: .done("Half a second\n")))
        #expect(await second.value == .init(reply: .done("Half a second\n")))
        #expect(try await comment(scene.c1, of: scene)["thread"] as? [[String: String]] != nil)
        #expect(try #require(scene.model.desk.open).comments.first { $0.id.rawValue == scene.c1 }?.thread.count == 2)
    }

    @Test func anotherQuestionOnTheCommentEndsTheAskThatWaitedOnTheOneBefore() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let scene = try await scene()

        let old = Task { await listener(.ask(id: scene.c1, text: "Slower by how much?", waitSeconds: nil), on: scene) }
        try await untilAsked(CommentID(rawValue: scene.c1), on: scene)
        let new = Task { await listener(.ask(id: scene.c1, text: "Or cut the scene?", waitSeconds: nil), on: scene) }
        let replaced = await old.value
        _ = await driver(.threadAnswer(id: scene.c1, text: "Cut it"), on: scene)

        #expect(replaced == .init(reply: .refused("another question was asked on \(scene.c1) since: `Or cut the scene?`")))
        #expect(await new.value == .init(reply: .done("Cut it\n")))
    }

    @Test func threadAnswerWithNoQuestionWaitingIsRefusedAndNeedsTheLease() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let scene = try await scene()

        let none = await driver(.threadAnswer(id: scene.c1, text: "yes"), on: scene)
        _ = await listener(.reply(id: scene.c1, text: "a message is not a question"), on: scene)
        let still = await driver(.threadAnswer(id: scene.c1, text: "yes"), on: scene)
        let unknown = await driver(.threadAnswer(id: "0badf00d-c1", text: "yes"), on: scene)
        // The operator holds the lease: another agent's answer is refused before the thread is reached.
        _ = await listener(.ask(id: scene.c1, text: "Which box?", waitSeconds: 0), on: scene)
        let other = await scene.server.reply(to: Wait.sent(.threadAnswer(id: scene.c1, text: "the left"), by: Wait.second))

        #expect(none == .init(reply: .refused("\(scene.c1) has no question waiting for an answer")))
        #expect(still == none)
        #expect(unknown == .init(reply: .refused("there is no comment `0badf00d-c1`")))
        #expect(!other.reply.ok)
        #expect(other.reply.error.hasPrefix("video-review is in use by Claude Code in /work"))
        #expect(try #require(scene.model.desk.open).comments.first { $0.id.rawValue == scene.c1 }?.openQuestion != nil)
    }

    @Test func anOpenAskIsAnsweredWhenTheAppQuitsAndALaterOneIsRefused() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let scene = try await scene()

        let asking = Task { await listener(.ask(id: scene.c1, text: "Slower by how much?", waitSeconds: nil), on: scene) }
        try await untilAsked(CommentID(rawValue: scene.c1), on: scene)
        scene.server.stop()

        #expect(await asking.value == .init(reply: .refused("video-review is quitting")))
        #expect(await listener(.ask(id: scene.c1, text: "Slower by how much?", waitSeconds: nil), on: scene)
            == .init(reply: .refused("video-review is quitting")))
    }

    // MARK: - The socket

    @Test func overTheSocketAnOpenAskIsKeptAliveByTheHeartbeatAndPrintsTheAnswerWhenItIsGiven() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let scene = try await scene()
        try scene.server.start()
        defer { scene.server.stop() }
        let socket = socket
        // A client that accepts a silence of a quarter second only: the heartbeat breaks it.
        let agent = ControlClient(socket: socket, holder: Wait.first, transport: UnixSocketTransport(), idleTimeout: 0.25)
        let driver = ControlClient(socket: socket, holder: Wait.operatorAgent, transport: UnixSocketTransport())
        let c2 = scene.c2

        let asking = Task { await Wait.sending { agent.send(.ask(id: c2, text: "Which box?", waitSeconds: 60)) } }
        try await untilAsked(CommentID(rawValue: c2), on: scene)
        try await Task.sleep(for: .milliseconds(600))
        let answered = await Wait.sending { driver.send(.threadAnswer(id: c2, text: "The left one")) }

        #expect(await asking.value == .success(.done("The left one\n")))
        #expect(answered == .success(.done("answered \(c2)\n")))
    }

    @Test func overTheSocketAnAskThatRunsOutAnswersWithNothingAndTheSameAskLaterGetsTheAnswer() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let scene = try await scene()
        try scene.server.start()
        defer { scene.server.stop() }
        let socket = socket
        let agent = ControlClient(socket: socket, holder: Wait.first, transport: UnixSocketTransport())
        let driver = ControlClient(socket: socket, holder: Wait.operatorAgent, transport: UnixSocketTransport())
        let c1 = scene.c1

        let ranOut = await Wait.sending { agent.send(.ask(id: c1, text: "Slower by how much?", waitSeconds: 1)) }
        _ = await Wait.sending { driver.send(.threadAnswer(id: c1, text: "Half a second")) }
        let again = await Wait.sending { agent.send(.ask(id: c1, text: "Slower by how much?", waitSeconds: 1)) }

        // What the command turns into exit 3.
        #expect(ranOut == .success(.done("")))
        #expect(again == .success(.done("Half a second\n")))
    }

    @Test func overTheSocketAnAskWhoseClientHasGoneStopsWaitingAndItsQuestionStaysOpen() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        // Nobody took the batch: the open ask alone shows the listener.
        let scene = try await scene(taken: false)
        try scene.server.start()
        defer { scene.server.stop() }

        let gone = UnixSocket.make()
        try #require(UnixSocket.connectSocket(gone, to: try #require(UnixSocket.address(socket.path))) == 0)
        _ = UnixSocket.writeAll(gone, Wait.sent(.ask(id: scene.c1, text: "Slower by how much?", waitSeconds: nil), by: Wait.first))
        UnixSocket.finishWriting(gone)
        try await until("listening", on: scene)
        close(gone)
        // The next heartbeat can't be written: the ask is over.
        try await until("absent", on: scene)

        #expect(try #require(scene.model.desk.open).comments.first { $0.id.rawValue == scene.c1 }?.openQuestion?.text == "Slower by how much?")
        // The answer is kept for the listener that asks again.
        _ = await driver(.threadAnswer(id: scene.c1, text: "Half a second"), on: scene)
        #expect(await listener(.ask(id: scene.c1, text: "Slower by how much?", waitSeconds: nil), on: scene) == .init(reply: .done("Half a second\n")))
    }
}
