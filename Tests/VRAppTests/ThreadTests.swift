import Foundation
import Testing
@testable import VRApp
import VRCommand
import VRLease
import VRReview
import VRWire

private let listener = Holder(key: "listener-1", name: "Claude Code", place: "/Users/me/shop")
private let other = Holder(key: "other-agent", name: "Claude Code", place: "/Users/me/elsewhere")

extension BatchRig {
    /// The fixture open, two comments sent as `b1` (`c2` at 4.5 s on a
    /// region, `c1` at 10 s) and taken by the listener's `wait`.
    fileprivate func delivered() async -> BatchRig {
        _ = await opened()
        await queueTwo()
        _ = await send(.batchSend)
        _ = await wait(by: listener)
        return self
    }

    /// A listener's request: sent with no lease.
    fileprivate func answer(_ request: ControlRequest, json: Bool = false) async -> ControlReply {
        await send(request, by: listener, json: json)
    }

    /// An `ask` sent without waiting for its answer, on the connection
    /// `ticket`; returns once the server holds it.
    fileprivate func ask(
        _ id: String, _ question: String, wait seconds: Int? = nil, json: Bool = false, ticket: UUID = UUID()
    ) async -> Task<ControlServer.Answer, Never> {
        let held = server.listeners.asks
        let request = ControlRequest.ask(commentID: id, question: question, waitSeconds: seconds)
        let asking = Task { await server.reply(to: ControlMessage(request, holder: listener, json: json).encoded(), ticket: ticket) }
        for _ in 0..<2_000 where server.listeners.asks == held {
            try? await Task.sleep(for: .milliseconds(1))
        }
        return asking
    }

    /// An `ask` answered as the socket would: the reply counts as written.
    fileprivate func asked(_ id: String, _ question: String, wait seconds: Int? = nil, json: Bool = false) async -> ControlReply {
        let request = ControlRequest.ask(commentID: id, question: question, waitSeconds: seconds)
        let answer = await server.reply(to: ControlMessage(request, holder: listener, json: json).encoded())
        server.written(answer, delivered: true)
        return answer.reply
    }

    fileprivate func comment(_ id: String) async throws -> [String: Any] {
        let comments = try #require(try await state()["comments"] as? [[String: Any]])
        return try #require(comments.first { $0["id"] as? String == id })
    }

    fileprivate func thread(of id: String) async throws -> [[String: String]] {
        try #require(try await comment(id)["thread"] as? [[String: String]])
    }

    fileprivate func batch() async throws -> [String: Any] {
        try #require((try await state()["batches"] as? [[String: Any]])?.first)
    }
}

/// A copy of the fixture video with other content: a free box at its end.
private func otherVideo(in folder: URL) throws -> URL {
    let copy = folder.appendingPathComponent("other.mp4")
    var data = try Data(contentsOf: fixtureVideo)
    data.append(contentsOf: [0, 0, 0, 8] + Array("free".utf8))
    try data.write(to: copy)
    return copy
}

@MainActor
@Suite struct AnswerTests {
    @Test func ackSetsEveryCommentOfTheBatchToAcknowledged() async throws {
        let rig = await BatchRig().delivered()

        #expect(await rig.answer(.ack(batchID: "b1", text: nil)) == .done("acknowledged b1\n"))

        #expect(try await rig.commentStates() == ["acknowledged", "acknowledged"])
        #expect(Timeline.markers(for: rig.model.comments, selection: nil).map(\.state) == [.acknowledged, .acknowledged])
        #expect(try await rig.batch()["thread"] as? [[String: String]] == [])
        // An ack without a text is no message: nothing to give notice of.
        #expect(rig.model.notices.isEmpty)
        #expect(await rig.answer(.ack(batchID: "b1", text: nil), json: true) == .done(#"{"id":"b1"}"# + "\n"))
    }

    @Test func ackWithATextShowsAsAMessageForTheFullBatch() async throws {
        let rig = await BatchRig().delivered()

        _ = await rig.answer(.ack(batchID: "b1", text: "on it"))

        #expect(try await rig.batch()["thread"] as? [[String: String]]
            == [["author": "agent", "kind": "message", "text": "on it", "at": "2025-10-04T12:00:00Z"]])
        #expect(rig.model.notices.map(\.title) == ["Agent · batch b1"])
        #expect(rig.model.notices.map(\.message.text) == ["on it"])
    }

    @Test func eachStatusShowsOnTheMarkerOfItsComment() async throws {
        let rig = await BatchRig().delivered()

        #expect(await rig.answer(.status(commentID: "c1", state: "working")) == .done("c1 is working\n"))
        #expect(Timeline.markers(for: rig.model.comments, selection: nil).map(\.state) == [.sent, .working])
        #expect(try await rig.commentStates() == ["sent", "working"])

        #expect(await rig.answer(.status(commentID: "c1", state: "done"), json: true) == .done(#"{"id":"c1","state":"done"}"# + "\n"))
        #expect(await rig.answer(.status(commentID: "c2", state: "failed")) == .done("c2 is failed\n"))
        #expect(Timeline.markers(for: rig.model.comments, selection: nil).map(\.state) == [.failed, .done])
        #expect(try await rig.commentStates() == ["failed", "done"])
    }

    @Test func aMoveTheStateMachineDoesNotAllowIsRefusedAndChangesNothing() async throws {
        let rig = await BatchRig().delivered()
        _ = await rig.answer(.status(commentID: "c1", state: "done"))
        _ = await rig.send(.commentAdd(text: "not sent", at: 15, region: nil))

        #expect(await rig.answer(.status(commentID: "c1", state: "working")) == .refused("c1 is done; it can't be set to working"))
        #expect(await rig.answer(.status(commentID: "c1", state: "failed")) == .refused("c1 is done; it can't be set to failed"))
        #expect(await rig.answer(.status(commentID: "c3", state: "working")) == .refused("c3 wasn't sent yet; it can't be given a status"))
        #expect(await rig.answer(.status(commentID: "c9", state: "done")) == .refused("there's no comment c9"))
        #expect(await rig.answer(.ack(batchID: "b9", text: nil)) == .refused("there's no batch b9"))
        #expect(await rig.answer(.reply(id: "x9", text: "hi")) == .refused("there's no comment or batch x9"))
        #expect(await rig.answer(.reply(id: "c3", text: "hi")) == .refused("c3 wasn't sent yet; it can't be replied on"))

        #expect(try await rig.commentStates() == ["sent", "done", "queued"])
        #expect(rig.model.notices.isEmpty)
    }

    @Test func aReplyShowsInTheThreadOfItsCommentAndAsANotice() async throws {
        let rig = await BatchRig().delivered()

        #expect(await rig.answer(.reply(id: "c1", text: "fixed in abc123")) == .done("replied on c1\n"))

        #expect(try await rig.thread(of: "c1")
            == [["author": "agent", "kind": "message", "text": "fixed in abc123", "at": "2025-10-04T12:00:00Z"]])
        #expect(try await rig.thread(of: "c2") == [])
        // What the card shows is the comment's own thread.
        #expect(rig.model.comments.first { $0.id == "c1" }?.thread.map(\.text) == ["fixed in abc123"])
        let notice = try #require(rig.model.notices.first)
        #expect(rig.model.notices.count == 1)
        #expect(notice.commentID == "c1")
        #expect(notice.title == "Agent · 0:10")
        #expect(notice.message.text == "fixed in abc123")
        let reported = try #require(try await rig.state()["notices"] as? [[String: Any]])
        #expect(reported.count == 1)
        #expect(reported[0]["commentId"] as? String == "c1")
        #expect(reported[0]["batchId"] as? String == "b1")
        #expect(reported[0]["kind"] as? String == "message")
        #expect(reported[0]["text"] as? String == "fixed in abc123")
    }

    @Test func aReplyOnABatchIdShowsAsAMessageForTheFullBatch() async throws {
        let rig = await BatchRig().delivered()

        #expect(await rig.answer(.reply(id: "b1", text: "both are in abc123"), json: true) == .done(#"{"id":"b1"}"# + "\n"))

        #expect(try await rig.batch()["thread"] as? [[String: String]]
            == [["author": "agent", "kind": "message", "text": "both are in abc123", "at": "2025-10-04T12:00:00Z"]])
        #expect(try await rig.thread(of: "c1") == [])
        #expect(try await rig.thread(of: "c2") == [])
        let reported = try #require(try await rig.state()["notices"] as? [[String: Any]])
        #expect(reported[0]["commentId"] is NSNull)
        #expect(reported[0]["batchId"] as? String == "b1")
        // The sidebar: the batch's header above the first of its comments.
        let rows = Sidebar.rows(comments: rig.model.comments, batches: rig.model.session?.batches ?? [])
        #expect(rows.map(\.id) == ["batch-b1", "c2", "c1"])
        guard case .batch(let header) = rows[0] else {
            Issue.record("the first row isn't the batch")
            return
        }
        #expect(header.thread.map(\.text) == ["both are in abc123"])
    }

    @Test func aNoticeGoesByItselfAndAClickShowsItsComment() async throws {
        let rig = await BatchRig().delivered()
        rig.model.noticeLifetime = .milliseconds(30)

        _ = await rig.answer(.reply(id: "c1", text: "first"))
        #expect(rig.model.notices.count == 1)
        await settle { rig.model.notices.isEmpty }
        #expect(rig.model.notices.isEmpty)

        rig.model.noticeLifetime = .seconds(60)
        _ = await rig.answer(.reply(id: "c1", text: "second"))
        rig.model.openNotice(try #require(rig.model.notices.first))
        await settle { rig.model.selection == "c1" }

        #expect(rig.model.notices.isEmpty)
        #expect(rig.model.selection == "c1")
        #expect(rig.player.time == 10)
    }

    @Test func stateAsLinesListsEachThreadUnderItsCommentAndItsBatch() async throws {
        let rig = await BatchRig().delivered()
        _ = await rig.answer(.ack(batchID: "b1", text: "on it"))
        _ = await rig.asked("c1", "which\npart?", wait: 0)
        _ = await rig.send(.threadAnswer(commentID: "c1", text: "the intro"))

        let lines = await rig.send(.state).output

        #expect(lines.contains("""
              c1 acknowledged at 0:10.000: too fast
                agent question: which part?
                person answer: the intro

            """))
        #expect(lines.contains("""
              b1 taken: c2, c1
                agent message: on it

            """))
    }

    @Test func aBatchIsFinishedWhenAllItsCommentsAreDoneOrFailedAndPresenceFollows() async throws {
        let rig = await BatchRig().delivered()
        let waiting = await rig.park(by: listener)
        #expect(try await rig.presence() == "working")

        _ = await rig.answer(.status(commentID: "c1", state: "done"))
        #expect(try await rig.batch()["finished"] as? Bool == false)
        #expect(try await rig.presence() == "working")

        _ = await rig.answer(.status(commentID: "c2", state: "failed"))

        #expect(try await rig.batch()["finished"] as? Bool == true)
        #expect(rig.model.outbox.parcels.isEmpty)
        #expect(try await rig.presence() == "listening")
        #expect(await rig.send(.state).output.contains("  b1 finished: c2, c1\n"))
        // A reply still reaches a finished comment.
        #expect(await rig.answer(.reply(id: "c1", text: "done in abc123")).ok)

        // The finished batch isn't given to another listener.
        rig.server.stop()
        _ = await waiting.value
        let next = await rig.wait(by: other, timeout: 0)
        #expect(next.reply.output.isEmpty)
    }

    @Test func aListenerAnswersWithNoLeaseWhileAnotherAgentHoldsItAndThreadAnswerNeedsIt() async throws {
        let rig = await BatchRig().delivered()
        // The operator of the rig holds the lease.
        #expect(try await rig.state()["lease"] is [String: Any])

        #expect(await rig.answer(.ack(batchID: "b1", text: nil)).ok)
        #expect(await rig.answer(.status(commentID: "c1", state: "working")).ok)
        #expect(await rig.answer(.reply(id: "c1", text: "looking")).ok)
        #expect(await rig.asked("c1", "which part?", wait: 0).ok)

        let refused = await rig.send(.threadAnswer(commentID: "c1", text: "the intro"), by: listener)
        #expect(!refused.ok)
        #expect(refused.error.contains("video-review is in use by Claude Code"))
        #expect(try await rig.thread(of: "c1").map { $0["kind"] } == ["message", "question"])
    }

    @Test func aListenerReachesAVideoThatIsNotTheOpenOne() async throws {
        let rig = await BatchRig().delivered()
        let another = try otherVideo(in: rig.library.root)
        #expect(await rig.send(.playerOpen(path: another.path)).ok)
        #expect((try await rig.state()["comments"] as? [[String: Any]])?.isEmpty == true)

        #expect(await rig.answer(.ack(batchID: "b1", text: "on it")).ok)
        #expect(await rig.answer(.reply(id: "c1", text: "fixed")).ok)
        #expect(await rig.answer(.status(commentID: "c1", state: "done")).ok)
        #expect(await rig.answer(.status(commentID: "c2", state: "done")).ok)
        let asking = await rig.ask("c2", "which button?")
        #expect(await rig.send(.threadAnswer(commentID: "c2", text: "the blue one")) == .done("answered c2\n"))
        #expect(await asking.value.reply == .done("the blue one\n"))
        #expect(rig.model.outbox.parcels.isEmpty)

        _ = await rig.send(.playerOpen(path: fixtureVideo.path))

        #expect(try await rig.commentStates() == ["done", "done"])
        #expect(try await rig.thread(of: "c1").map { $0["text"] } == ["fixed"])
        #expect(try await rig.thread(of: "c2").map { $0["kind"] } == ["question", "answer"])
        #expect((try await rig.batch()["thread"] as? [[String: String]])?.map { $0["text"] } == ["on it"])
    }
}

@MainActor
@Suite struct AskTests {
    @Test func anAskParksUntilThreadAnswerGivesTheAnswer() async throws {
        let rig = await BatchRig().delivered()

        let asking = await rig.ask("c1", "which part?")

        #expect(rig.server.listeners.asks == 1)
        #expect(try await rig.thread(of: "c1")
            == [["author": "agent", "kind": "question", "text": "which part?", "at": "2025-10-04T12:00:00Z"]])
        #expect(rig.model.notices.map(\.title) == ["Agent asks · 0:10"])
        // The card's edge and its pin say the agent waits.
        #expect(rig.model.comments.map { $0.openQuestion != nil } == [false, true])
        #expect(Timeline.markers(for: rig.model.comments, selection: nil).map(\.hasOpenQuestion) == [false, true])

        rig.clock.set(1_759_579_260)
        #expect(await rig.send(.threadAnswer(commentID: "c1", text: " the intro ")) == .done("answered c1\n"))
        let answer = await asking.value

        #expect(answer.reply == .done("the intro\n"))
        #expect(answer.heard == "c1")
        #expect(rig.server.listeners.asks == 0)
        #expect(try await rig.thread(of: "c1") == [
            ["author": "agent", "kind": "question", "text": "which part?", "at": "2025-10-04T12:00:00Z"],
            ["author": "person", "kind": "answer", "text": "the intro", "at": "2025-10-04T12:01:00Z"],
        ])
        #expect(Timeline.markers(for: rig.model.comments, selection: nil).map(\.hasOpenQuestion) == [false, false])
    }

    @Test func anAskExitsWithTheAnswerThePersonTypesInTheAnswerBox() async throws {
        let rig = await BatchRig().delivered()
        let asking = await rig.ask("c2", "which button?", json: true)

        // Empty text is refused, and the question stays open.
        #expect(!rig.model.answerByPerson("c2", text: "  "))
        #expect(rig.server.listeners.asks == 1)
        rig.clock.set(1_759_579_230)
        #expect(rig.model.answerByPerson("c2", text: "the blue one"))

        #expect(await asking.value.reply == .done(
            #"{"answer":"the blue one","answeredAt":"2025-10-04T12:00:30Z","commentId":"c2","question":"which button?"}"# + "\n"
        ))
        // No lease was taken: the person answered.
        #expect(try await rig.thread(of: "c2").map { $0["author"] } == ["agent", "person"])
        #expect(!rig.model.answerByPerson("c2", text: "again"))
    }

    @Test func threadAnswerAsJSONNamesTheCommentAndWithNoQuestionIsRefused() async throws {
        let rig = await BatchRig().delivered()

        #expect(await rig.send(.threadAnswer(commentID: "c1", text: "yes")) == .refused("c1 has no question to answer"))
        #expect(await rig.send(.threadAnswer(commentID: "c9", text: "yes")) == .refused("there's no comment c9"))
        let asking = await rig.ask("c1", "which part?")
        #expect(await rig.send(.threadAnswer(commentID: "c1", text: "yes"), json: true) == .done(#"{"id":"c1"}"# + "\n"))
        _ = await asking.value
    }

    @Test func anAskWhoseTimeRanOutIsDoneWithNothingToPrintAndItsQuestionStaysOpen() async throws {
        let rig = await BatchRig().delivered()

        #expect(await rig.asked("c1", "which part?", wait: 0) == .done("", note: "no answer came within 0 seconds\n"))
        let asking = await rig.ask("c2", "which button?", wait: 1)
        let answer = await asking.value

        #expect(answer.reply == .done("", note: "no answer came within 1 second\n"))
        #expect(answer.heard == nil)
        #expect(rig.server.listeners.asks == 0)
        #expect(rig.model.comments.map { $0.openQuestion?.text } == ["which button?", "which part?"])
    }

    @Test func aLateAnswerIsReturnedOnceByARepeatedAsk() async throws {
        let rig = await BatchRig().delivered()
        _ = await rig.asked("c1", "which part?", wait: 0)

        #expect(await rig.send(.threadAnswer(commentID: "c1", text: "the intro")).ok)
        // The repeated ask gets the answer at once, whatever it waits for.
        #expect(await rig.asked("c1", "which part?", wait: 0) == .done("the intro\n"))
        #expect(try await rig.thread(of: "c1").count == 2)

        // Given once: the next ask is a new question, and waits.
        #expect(await rig.asked("c1", "the first intro?", wait: 0) == .done("", note: "no answer came within 0 seconds\n"))
        #expect(try await rig.thread(of: "c1").map { $0["kind"] } == ["question", "answer", "question"])
    }

    @Test func anAnswerWhoseReplyCouldNotBeWrittenIsGivenToTheNextAsk() async throws {
        let rig = await BatchRig().delivered()
        let asking = await rig.ask("c1", "which part?")
        _ = await rig.send(.threadAnswer(commentID: "c1", text: "the intro"))
        let answer = await asking.value
        #expect(answer.hangsOnDelivery)

        // The listener's command was gone when the reply was written.
        rig.server.written(answer, delivered: false)

        #expect(await rig.asked("c1", "which part?", json: true).output.contains(#""answer":"the intro""#))
        #expect(await rig.asked("c1", "and then?", wait: 0).output.isEmpty)
    }

    @Test func theOpenQuestionAskedAgainWaitsOnWithoutASecondQuestionOrNotice() async throws {
        let rig = await BatchRig().delivered()
        _ = await rig.asked("c1", "which part?", wait: 0)

        let asking = await rig.ask("c1", "which part?")
        #expect(try await rig.thread(of: "c1").count == 1)
        #expect(rig.model.notices.count == 1)
        #expect(await rig.asked("c1", "and why?", wait: 0)
            == .refused("c1 has a question the person hasn't answered: which part?"))

        _ = await rig.send(.threadAnswer(commentID: "c1", text: "the intro"))
        #expect(await asking.value.reply == .done("the intro\n"))
    }

    @Test func anAskThatCannotBeAskedIsRefused() async throws {
        let rig = await BatchRig().delivered()
        _ = await rig.send(.commentAdd(text: "not sent", at: 15, region: nil))

        #expect(await rig.asked("c9", "why?") == .refused("there's no comment c9"))
        #expect(await rig.asked("c3", "why?") == .refused("c3 wasn't sent yet; it can't be asked about"))
        #expect(rig.server.listeners.asks == 0)
    }

    @Test func anAskWhoseListenerWentAwayClosesAndItsQuestionStaysForTheNextAsk() async throws {
        let rig = await BatchRig().delivered()
        let waiting = await rig.park(by: listener)
        let ticket = UUID()
        let asking = await rig.ask("c1", "which part?", ticket: ticket)

        rig.server.dropped(ticket)

        #expect(await asking.value.reply == .refused("the listener went away"))
        #expect(rig.server.listeners.asks == 0)
        // The ask isn't the listener's presence: its wait is still open.
        #expect(rig.server.listeners.waiting == 1)
        #expect(try await rig.presence() == "working")
        #expect(rig.model.comments.last?.openQuestion?.text == "which part?")
        rig.server.stop()
        _ = await waiting.value
    }

    @Test func aParkedAskHearsTheAppQuit() async {
        let rig = await BatchRig().delivered()
        let asking = await rig.ask("c1", "which part?")

        rig.server.stop()

        #expect(await asking.value.reply == .refused("video-review is quitting"))
    }
}

/// The `ask` and `thread answer` commands and the server joined by a real
/// socket: the heartbeat keeps the ask's connection, and the command prints
/// the answer.
@MainActor
@Suite struct AskSocketTests {
    @Test func theAskCommandExitsWithTheAnswerThreadAnswerGives() async throws {
        let support = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("vr-\(UUID().uuidString.prefix(8))", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: support) }
        let rig = await BatchRig(socket: ControlSocket.url(in: support)).delivered()
        try rig.server.start()
        defer { rig.server.stop() }

        let table = CommandTable.standard
        var listening = CommandEnvironment.system()
        listening.variables = [AppIdentity.supportVariable: support.path, Holder.keyVariable: "listener-socket"]
        var operating = listening
        // The rig's operator holds the lease.
        operating.variables[Holder.keyVariable] = "operator"
        // Off the main actor: a command blocks on the socket while the
        // server answers on the main actor.
        func run(_ arguments: [String], as environment: CommandEnvironment) async -> CommandResult {
            await Task.detached { table.run(arguments, environment: environment) }.value
        }

        #expect(await run(["ack", "b1", "on it"], as: listening) == CommandResult(output: "acknowledged b1\n"))
        #expect(await run(["status", "c1", "working"], as: listening) == CommandResult(output: "c1 is working\n"))
        #expect(await run(["ask", "c1", "which part?", "--wait", "0"], as: listening)
            == CommandResult(error: "no answer came within 0 seconds\n", status: 3))

        let asking = Task.detached { [listening] in table.run(["ask", "c1", "which part?", "--wait", "30", "--json"], environment: listening) }
        await settle { rig.server.listeners.asks == 1 }
        #expect(await run(["thread", "answer", "c1", "the intro"], as: operating) == CommandResult(output: "answered c1\n"))
        let result = await asking.value

        #expect(result.status == 0)
        #expect(result.error.isEmpty)
        let answer = try #require(try JSONSerialization.jsonObject(with: Data(result.output.utf8)) as? [String: String])
        #expect(answer["commentId"] == "c1")
        #expect(answer["question"] == "which part?")
        #expect(answer["answer"] == "the intro")
        #expect(answer["answeredAt"] == "2025-10-04T12:00:00Z")
        // The reply was written: the answer isn't given again.
        await settle { rig.model.unheardAnswer(on: "c1") == nil }
        #expect(rig.model.unheardAnswer(on: "c1") == nil)

        #expect(await run(["reply", "c1", "done in abc123"], as: listening) == CommandResult(output: "replied on c1\n"))
        #expect(await run(["status", "c1", "done"], as: listening) == CommandResult(output: "c1 is done\n"))
        #expect(await run(["status", "c1", "working"], as: listening)
            == CommandResult(error: "c1 is done; it can't be set to working\n", status: 1))
        #expect(await run(["thread", "answer", "c1", "again"], as: listening).status == 1)
        #expect(try await rig.thread(of: "c1").map { $0["kind"] } == ["question", "answer", "message"])
    }
}

/// Waits for work a task does in the background, at most 2 seconds.
@MainActor
private func settle(until done: () -> Bool) async {
    for _ in 0..<2_000 where !done() {
        try? await Task.sleep(for: .milliseconds(1))
    }
}
