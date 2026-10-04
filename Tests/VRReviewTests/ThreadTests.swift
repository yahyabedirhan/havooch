import Foundation
import Testing
import VRReview

private let video = VideoInfo(path: "/Users/me/sample.mp4", contentHash: "abc", duration: 21.233, title: "sample")
private let noon = Date(timeIntervalSince1970: 1_759_579_200)

/// A review with the batch `b1` of two sent comments, `c1` at 10 s and `c2`
/// at 12 s, and one comment still queued, `c3`.
private func sentSession() throws -> ReviewSession {
    var session = ReviewSession(video: video)
    for (id, time) in [("c1", 10.0), ("c2", 12)] {
        session.draft(id: id, time: time)
        try session.commit(id, text: id)
    }
    _ = try session.send(batchID: "b1", at: noon)
    session.draft(id: "c3", time: 15)
    try session.commit("c3", text: "later")
    return session
}

private func refusal(_ body: () throws(ReviewRefusal) -> Void) -> String? {
    do throws(ReviewRefusal) {
        try body()
        return nil
    } catch {
        return error.reason
    }
}

private func states(_ session: ReviewSession) -> [CommentState] {
    session.comments.map(\.state)
}

@Suite struct AcknowledgeTests {
    @Test func ackSetsEveryCommentOfTheBatchToAcknowledged() throws {
        var session = try sentSession()

        try session.acknowledge("b1", at: noon)

        #expect(states(session) == [.acknowledged, .acknowledged, .queued])
        #expect(session.batch("b1")?.thread == [])
    }

    @Test func ackWithATextIsAMessageForTheFullBatch() throws {
        var session = try sentSession()

        try session.acknowledge("b1", text: " on it\n", at: noon)

        #expect(session.batch("b1")?.thread == [ThreadMessage(author: .agent, kind: .message, text: "on it", at: noon)])
        #expect(session.comments.allSatisfy { $0.thread.isEmpty })
    }

    @Test func ackLeavesACommentThatMovedOnAsItIs() throws {
        var session = try sentSession()
        try session.setStatus("c1", to: .working)
        try session.setStatus("c2", to: .done)

        try session.acknowledge("b1", at: noon)
        try session.acknowledge("b1", at: noon)

        #expect(states(session) == [.working, .done, .queued])
    }

    @Test func ackOfABatchThatIsNotThereOrWithAnEmptyTextIsRefused() throws {
        var session = try sentSession()

        #expect(refusal { () throws(ReviewRefusal) in try session.acknowledge("b9", at: noon) } == "there's no batch b9")
        #expect(refusal { () throws(ReviewRefusal) in try session.acknowledge("b1", text: "  ", at: noon) } == "a message needs its text")
        // A refused ack changes nothing.
        #expect(states(session) == [.sent, .sent, .queued])
    }
}

@Suite struct StatusTests {
    @Test(arguments: [CommentState.working, .done, .failed])
    func eachStatusIsSetFromSentAndFromAcknowledged(status: CommentState) throws {
        var session = try sentSession()
        try session.setStatus("c1", to: status)
        try session.acknowledge("b1", at: noon)
        try session.setStatus("c2", to: status)

        #expect(states(session) == [status, status, .queued])
    }

    @Test func aStatusMaySkipForwardAndWorkingLeadsToDoneOrFailed() throws {
        var session = try sentSession()
        try session.acknowledge("b1", at: noon)

        try session.setStatus("c1", to: .done)
        try session.setStatus("c2", to: .working)
        try session.setStatus("c2", to: .failed)

        #expect(states(session) == [.done, .failed, .queued])
    }

    @Test func doneAndFailedAreFinal() throws {
        var session = try sentSession()
        try session.setStatus("c1", to: .done)
        try session.setStatus("c2", to: .failed)

        #expect(refusal { () throws(ReviewRefusal) in try session.setStatus("c1", to: .working) } == "c1 is done; it can't be set to working")
        #expect(refusal { () throws(ReviewRefusal) in try session.setStatus("c1", to: .failed) } == "c1 is done; it can't be set to failed")
        #expect(refusal { () throws(ReviewRefusal) in try session.setStatus("c2", to: .done) } == "c2 is failed; it can't be set to done")
        #expect(states(session) == [.done, .failed, .queued])
    }

    @Test func theStatusACommentAlreadyHasIsSetAgainWithoutAChange() throws {
        var session = try sentSession()
        try session.setStatus("c1", to: .working)
        try session.setStatus("c1", to: .working)
        try session.setStatus("c1", to: .done)
        try session.setStatus("c1", to: .done)

        #expect(session.comment("c1")?.state == .done)
    }

    @Test func whatIsNotAStatusOrNotASentCommentIsRefused() throws {
        var session = try sentSession()

        #expect(refusal { () throws(ReviewRefusal) in try session.setStatus("c3", to: .working) } == "c3 wasn't sent yet; it can't be given a status")
        #expect(refusal { () throws(ReviewRefusal) in try session.setStatus("c9", to: .done) } == "there's no comment c9")
        for state in [CommentState.draft, .queued, .sent, .acknowledged] {
            #expect(refusal { () throws(ReviewRefusal) in try session.setStatus("c1", to: state) }
                == "a comment's status is working, done or failed, not \(state.rawValue)")
        }
        #expect(states(session) == [.sent, .sent, .queued])
    }

    @Test func aBatchIsFinishedWhenEveryCommentIsDoneOrFailed() throws {
        var session = try sentSession()
        try session.setStatus("c1", to: .done)
        #expect(!session.isFinished("b1"))

        try session.setStatus("c2", to: .failed)

        #expect(session.isFinished("b1"))
    }
}

@Suite struct ThreadTests {
    @Test func aReplyGoesInTheThreadOfItsCommentWithItsAuthorAndKind() throws {
        var session = try sentSession()

        let place = try session.reply(to: "c1", text: " fixed in abc123 ", at: noon)

        #expect(place == .comment("c1"))
        #expect(session.comment("c1")?.thread == [ThreadMessage(author: .agent, kind: .message, text: "fixed in abc123", at: noon)])
        #expect(session.comment("c2")?.thread == [])
        #expect(session.batch("b1")?.thread == [])
    }

    @Test func aReplyOnABatchIdIsAMessageForTheFullBatch() throws {
        var session = try sentSession()

        let place = try session.reply(to: "b1", text: "all done", at: noon)

        #expect(place == .batch("b1"))
        #expect(session.batch("b1")?.thread == [ThreadMessage(author: .agent, kind: .message, text: "all done", at: noon)])
        #expect(session.comments.allSatisfy { $0.thread.isEmpty })
    }

    @Test func aReplyIsAllowedOnAFinishedComment() throws {
        var session = try sentSession()
        try session.setStatus("c1", to: .done)

        try session.reply(to: "c1", text: "done in abc123", at: noon)

        #expect(session.comment("c1")?.thread.count == 1)
    }

    @Test func aReplyThatCannotBeWrittenIsRefused() throws {
        var session = try sentSession()

        #expect(refusal { () throws(ReviewRefusal) in try session.reply(to: "x1", text: "hi", at: noon) } == "there's no comment or batch x1")
        #expect(refusal { () throws(ReviewRefusal) in try session.reply(to: "c3", text: "hi", at: noon) } == "c3 wasn't sent yet; it can't be replied on")
        #expect(refusal { () throws(ReviewRefusal) in try session.reply(to: "c1", text: " ", at: noon) } == "a message needs its text")
        #expect(session.comments.allSatisfy { $0.thread.isEmpty })
    }

    @Test func aQuestionIsOpenUntilThePersonAnswersIt() throws {
        var session = try sentSession()
        let later = noon.addingTimeInterval(30)

        try session.ask("c1", question: "which part?", at: noon)
        let question = ThreadMessage(author: .agent, kind: .question, text: "which part?", at: noon)
        #expect(session.openQuestion(on: "c1") == question)
        #expect(session.unheardAnswer(on: "c1") == nil)

        try session.answer("c1", text: " the intro ", at: later)

        let answer = ThreadMessage(author: .person, kind: .answer, text: "the intro", at: later)
        #expect(session.comment("c1")?.thread == [question, answer])
        #expect(session.openQuestion(on: "c1") == nil)
        #expect(session.unheardAnswer(on: "c1") == ReviewSession.Exchange(question: question, answer: answer))
    }

    @Test func anAnswerIsGivenToAnAskOnce() throws {
        var session = try sentSession()
        try session.ask("c1", question: "which part?", at: noon)
        try session.answer("c1", text: "the intro", at: noon)

        session.answerHeard("c1")

        #expect(session.unheardAnswer(on: "c1") == nil)
        #expect(session.comment("c1")?.thread.count == 2)
    }

    @Test func aMessageAfterAQuestionLeavesItOpen() throws {
        var session = try sentSession()
        try session.ask("c1", question: "which part?", at: noon)

        try session.reply(to: "c1", text: "meanwhile, I started", at: noon)

        #expect(session.openQuestion(on: "c1")?.text == "which part?")
        try session.answer("c1", text: "the intro", at: noon)
        #expect(session.unheardAnswer(on: "c1")?.question.text == "which part?")
    }

    @Test func oneQuestionAtATimeAndTheSameOneAskedAgainAddsNothing() throws {
        var session = try sentSession()
        try session.ask("c1", question: "which part?", at: noon)

        #expect(refusal { () throws(ReviewRefusal) in try session.ask("c1", question: "and why?", at: noon) }
            == "c1 has a question the person hasn't answered: which part?")
        try session.ask("c1", question: " which part? ", at: noon)

        #expect(session.comment("c1")?.thread.count == 1)
        // Another comment has its own question.
        try session.ask("c2", question: "and why?", at: noon)
        #expect(session.openQuestion(on: "c2")?.text == "and why?")
    }

    @Test func aNewQuestionAfterAnAnswerThatWasHeardIsOpen() throws {
        var session = try sentSession()
        try session.ask("c1", question: "which part?", at: noon)
        try session.answer("c1", text: "the intro", at: noon)
        session.answerHeard("c1")

        try session.ask("c1", question: "the first intro?", at: noon)

        #expect(session.unheardAnswer(on: "c1") == nil)
        #expect(session.openQuestion(on: "c1")?.text == "the first intro?")
        #expect(session.comment("c1")?.thread.map(\.kind) == [.question, .answer, .question])
    }

    @Test func anAnswerNeedsAnOpenQuestionAndItsText() throws {
        var session = try sentSession()

        #expect(refusal { () throws(ReviewRefusal) in try session.answer("c1", text: "yes", at: noon) } == "c1 has no question to answer")
        #expect(refusal { () throws(ReviewRefusal) in try session.answer("c9", text: "yes", at: noon) } == "there's no comment c9")
        try session.ask("c1", question: "which part?", at: noon)
        #expect(refusal { () throws(ReviewRefusal) in try session.answer("c1", text: "\n", at: noon) } == "a message needs its text")
        try session.answer("c1", text: "yes", at: noon)
        #expect(refusal { () throws(ReviewRefusal) in try session.answer("c1", text: "and no", at: noon) } == "c1 has no question to answer")
    }

    @Test func aQuestionNeedsASentCommentAndItsText() throws {
        var session = try sentSession()

        #expect(refusal { () throws(ReviewRefusal) in try session.ask("c3", question: "why?", at: noon) } == "c3 wasn't sent yet; it can't be asked about")
        #expect(refusal { () throws(ReviewRefusal) in try session.ask("c1", question: "", at: noon) } == "a message needs its text")
        #expect(refusal { () throws(ReviewRefusal) in try session.ask("c9", question: "why?", at: noon) } == "there's no comment c9")
    }

    @Test func threadsAndUnheardAnswersAreKeptWithTheReview() throws {
        var session = try sentSession()
        try session.acknowledge("b1", text: "on it", at: noon)
        try session.ask("c1", question: "which part?", at: noon)
        try session.answer("c1", text: "the intro", at: noon)
        try session.reply(to: "c2", text: "done", at: noon)

        let kept = try JSONDecoder().decode(ReviewSession.self, from: JSONEncoder().encode(session))

        #expect(kept == session)
        #expect(kept.unheardAnswer(on: "c1")?.answer.text == "the intro")
        #expect(kept.comment("c1")?.thread.map(\.author) == [.agent, .person])
        #expect(kept.comment("c1")?.thread.map(\.kind) == [.question, .answer])
    }

    @Test func aReviewKeptBeforeThreadsReadsWithNone() throws {
        let json = """
            {"video":{"path":"/Users/me/sample.mp4","contentHash":"abc","duration":21.233,"title":"sample"},
             "comments":[{"id":"c1","time":10,"text":"too fast","state":"sent","batchID":"b1"}],
             "batches":[{"id":"b1","sentAt":0,"commentIDs":["c1"]}]}
            """
        let session = try JSONDecoder().decode(ReviewSession.self, from: Data(json.utf8))

        #expect(session.comment("c1")?.thread == [])
        #expect(session.batch("b1")?.thread == [])
        #expect(session.unheard == [])
    }

    @Test func aRequeueKeepsTheThreads() throws {
        var session = try sentSession()
        try session.acknowledge("b1", text: "on it", at: noon)
        try session.ask("c1", question: "which part?", at: noon)

        session.requeue("b1")

        #expect(states(session) == [.sent, .sent, .queued])
        #expect(session.openQuestion(on: "c1")?.text == "which part?")
        #expect(session.batch("b1")?.thread.count == 1)
    }
}
