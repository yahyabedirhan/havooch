import Foundation
import Testing
import VRReview

/// What a listener and the person make of a sent comment: its status, its
/// thread, and the batch's own messages.
@Suite struct ReviewAnswerTests {
    static let hash = "7f3a9c21" + String(repeating: "0", count: 56)
    static let c1 = CommentID(rawValue: "7f3a9c21-c1")
    static let c2 = CommentID(rawValue: "7f3a9c21-c2")
    static let b1 = BatchID(rawValue: "7f3a9c21-b1")
    let now = Date(timeIntervalSince1970: 1_000)

    private func empty() -> Review {
        Review(video: VideoInfo(contentHash: Self.hash, path: "/videos/sample.mp4", title: "sample", duration: 21.233))
    }

    /// A review with `c1` at 10 s and `c2` at 4 s, both sent in `b1`.
    private func sent() throws -> Review {
        var review = empty()
        try review.addComment(text: "too fast", time: 10, now: now)
        try review.addComment(text: "this box", time: 4, now: now)
        try review.sendBatch(now: now)
        return review
    }

    /// A review whose `c1` stands at `state`, reached by the rules alone.
    private func review(c1 state: CommentState) throws -> Review {
        if state == .queued {
            var review = empty()
            try review.addComment(text: "too fast", time: 10, now: now)
            return review
        }
        var review = try sent()
        switch state {
        case .acknowledged:
            try review.acknowledge(Self.b1, now: now)
        case .working, .done, .failed:
            try review.setStatus(Self.c1, to: state)
        default:
            break
        }
        #expect(try review.comment(Self.c1).state == state)
        return review
    }

    // MARK: - Statuses

    @Test func acknowledgingABatchSetsItsCommentsToAcknowledgedAndKeepsItsTextAsABatchMessage() throws {
        var review = try sent()

        let plain = try review.acknowledge(Self.b1, now: now)
        #expect(review.comments.map(\.state) == [.acknowledged, .acknowledged])
        #expect(plain.thread.isEmpty)

        let said = try review.acknowledge(Self.b1, text: "  got it  ", now: now + 5)
        #expect(said.thread == [ThreadMessage(author: .agent, kind: .message, text: "got it", at: now + 5)])
        #expect(review.comments.map(\.thread.count) == [0, 0])
    }

    @Test func acknowledgingMovesNoCommentBack() throws {
        var review = try sent()
        try review.setStatus(Self.c1, to: .working)
        try review.setStatus(Self.c2, to: .done)

        try review.acknowledge(Self.b1, now: now)

        #expect(try review.comment(Self.c1).state == .working)
        #expect(try review.comment(Self.c2).state == .done)
    }

    @Test func acknowledgingABatchThatIsNotThereIsRefused() throws {
        var review = try sent()
        #expect(throws: ReviewError.unknownBatch("7f3a9c21-b9")) { try review.acknowledge(BatchID(rawValue: "7f3a9c21-b9"), now: now) }
    }

    /// Every move a status may and may not make, as one table.
    @Test func aStatusMovesForwardOnlyMaySkipAStepAndDoneAndFailedAreFinal() throws {
        let allowed: [CommentState: Set<CommentState>] = [
            .queued: [],
            .sent: [.working, .done, .failed],
            .acknowledged: [.working, .done, .failed],
            .working: [.done, .failed],
            .done: [],
            .failed: [],
        ]
        for (from, moves) in allowed {
            for to in CommentState.allCases {
                var review = try review(c1: from)
                if moves.contains(to) {
                    #expect(try review.setStatus(Self.c1, to: to).state == to, "\(from) to \(to)")
                } else {
                    #expect(throws: ReviewError.illegalMove(Self.c1, from: from, to: to), "\(from) to \(to)") {
                        try review.setStatus(Self.c1, to: to)
                    }
                    #expect(try review.comment(Self.c1).state == from)
                }
            }
        }
    }

    @Test func aRefusedMoveSaysWhereTheCommentStands() {
        #expect(ReviewError.illegalMove(Self.c1, from: .done, to: .working).message
            == "7f3a9c21-c1 is done and can't become working; a comment only moves forward: "
            + "sent, acknowledged, working, then done or failed, which are final")
    }

    @Test func aBatchIsFinishedOnceEachOfItsCommentsIsDoneOrFailed() throws {
        var review = try sent()
        try review.setStatus(Self.c1, to: .done)
        #expect(!review.isFinished(Self.b1))
        try review.setStatus(Self.c2, to: .failed)
        #expect(review.isFinished(Self.b1))
    }

    // MARK: - Threads

    @Test func aThreadKeepsEachMessagesAuthorAndKindInTheOrderTheyCame() throws {
        var review = try sent()

        try review.reply(toComment: Self.c1, text: "looking at the pacing", now: now + 1)
        try review.ask(Self.c1, question: "Slower by how much?", now: now + 2)
        try review.answer(Self.c1, text: "Half a second per scene", now: now + 3)
        try review.reply(toComment: Self.c1, text: "done in a1b2c3", now: now + 4)

        #expect(try review.comment(Self.c1).thread == [
            ThreadMessage(author: .agent, kind: .message, text: "looking at the pacing", at: now + 1),
            ThreadMessage(author: .agent, kind: .question, text: "Slower by how much?", at: now + 2),
            ThreadMessage(author: .person, kind: .answer, text: "Half a second per scene", at: now + 3),
            ThreadMessage(author: .agent, kind: .message, text: "done in a1b2c3", at: now + 4),
        ])
        #expect(try review.comment(Self.c2).thread.isEmpty)
        // A stored review brings the thread back as it was.
        #expect(try JSONDecoder().decode(Review.self, from: JSONEncoder().encode(review)) == review)
    }

    @Test func aReplyToABatchIsAMessageForTheWholeBatch() throws {
        var review = try sent()

        let batch = try review.reply(toBatch: Self.b1, text: "both changes are in a1b2c3", now: now + 9)

        #expect(batch.thread == [ThreadMessage(author: .agent, kind: .message, text: "both changes are in a1b2c3", at: now + 9)])
        #expect(try review.batch(Self.b1).thread == batch.thread)
        #expect(review.comments.map(\.thread.count) == [0, 0])
    }

    @Test func aQuestionWaitsUntilThePersonAnswersIt() throws {
        var review = try sent()
        #expect(try review.comment(Self.c1).openQuestion == nil)

        let asked = try review.ask(Self.c1, question: "Which box?", now: now)
        #expect(asked.openQuestion?.text == "Which box?")
        #expect(asked.lastAnswer == nil)

        let answered = try review.answer(Self.c1, text: "The left one", now: now + 1)
        #expect(answered.openQuestion == nil)
        #expect(answered.lastAnswer?.text == "The left one")
    }

    @Test func theSameQuestionAskedAgainIsNotPostedTwiceAnsweredOrNot() throws {
        var review = try sent()
        try review.ask(Self.c1, question: "Which box?", now: now)
        #expect(try review.ask(Self.c1, question: " Which box? ", now: now + 1).thread.count == 1)

        try review.answer(Self.c1, text: "The left one", now: now + 2)
        let again = try review.ask(Self.c1, question: "Which box?", now: now + 3)
        #expect(again.thread.count == 2)
        #expect(again.lastAnswer?.text == "The left one")

        // Another question is a new one, and waits for its own answer.
        let next = try review.ask(Self.c1, question: "And the right one?", now: now + 4)
        #expect(next.thread.count == 3)
        #expect(next.openQuestion?.text == "And the right one?")
        #expect(next.lastAnswer == nil)
    }

    @Test func anAnswerWithNoQuestionWaitingIsRefused() throws {
        var review = try sent()
        #expect(throws: ReviewError.noOpenQuestion(Self.c1)) { try review.answer(Self.c1, text: "yes", now: now) }

        try review.reply(toComment: Self.c1, text: "a message is not a question", now: now)
        #expect(throws: ReviewError.noOpenQuestion(Self.c1)) { try review.answer(Self.c1, text: "yes", now: now) }

        try review.ask(Self.c1, question: "Which box?", now: now)
        try review.answer(Self.c1, text: "The left one", now: now)
        // Answered: nothing waits any more.
        #expect(throws: ReviewError.noOpenQuestion(Self.c1)) { try review.answer(Self.c1, text: "or the right", now: now) }
        #expect(ReviewError.noOpenQuestion(Self.c1).message == "7f3a9c21-c1 has no question waiting for an answer")
    }

    @Test func aMessageWithoutTextIsRefusedAndPostsNothing() throws {
        var review = try sent()
        #expect(throws: ReviewError.emptyMessage) { try review.reply(toComment: Self.c1, text: "  ", now: now) }
        #expect(throws: ReviewError.emptyMessage) { try review.reply(toBatch: Self.b1, text: "", now: now) }
        #expect(throws: ReviewError.emptyMessage) { try review.ask(Self.c1, question: "\n", now: now) }
        try review.ask(Self.c1, question: "Which box?", now: now)
        #expect(throws: ReviewError.emptyMessage) { try review.answer(Self.c1, text: " ", now: now) }
        #expect(try review.comment(Self.c1).thread.count == 1)
        #expect(try review.batch(Self.b1).thread.isEmpty)
    }

    @Test func aListenerAnswersOnlyACommentThatWasSent() throws {
        var review = try review(c1: .queued)
        #expect(throws: ReviewError.notSent(Self.c1, .queued)) { try review.reply(toComment: Self.c1, text: "hello", now: now) }
        #expect(throws: ReviewError.notSent(Self.c1, .queued)) { try review.ask(Self.c1, question: "why?", now: now) }
        #expect(throws: ReviewError.unknownComment("7f3a9c21-c9")) {
            try review.reply(toComment: CommentID(rawValue: "7f3a9c21-c9"), text: "hello", now: now)
        }
    }

    @Test func aBatchSentAgainKeepsItsThreadsAndPutsItsUnfinishedCommentsBack() throws {
        var review = try sent()
        try review.acknowledge(Self.b1, text: "got it", now: now)
        try review.reply(toComment: Self.c1, text: "on it", now: now)
        try review.setStatus(Self.c1, to: .working)
        try review.setStatus(Self.c2, to: .done)

        review.requeue(Self.b1)

        #expect(try review.comment(Self.c1).state == .sent)
        #expect(try review.comment(Self.c2).state == .done)
        #expect(try review.comment(Self.c1).thread.count == 1)
        #expect(try review.batch(Self.b1).thread.count == 1)
    }
}
