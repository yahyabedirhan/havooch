import Foundation
import ReviewCore
import Testing

@Suite("The listener's answers on a review")
struct ThreadTests {
    static let batch = ItemID("b-00000001")!
    static let first = ItemID("c-00000001")!
    static let second = ItemID("c-00000002")!
    static let queued = ItemID("c-00000003")!
    static let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func message(_ number: Int) -> ItemID { ItemID("m-0000000\(number)")! }

    /// Two comments sent as one batch, and a third queued after it.
    private func sent() throws -> VideoReview {
        var review = VideoReview(video: VideoInfo(contentHash: "abc", title: "sample", duration: 21.233, path: "/videos/sample.mp4"))
        try review.addComment(id: Self.first, time: 5, text: "Too fast")
        try review.addComment(id: Self.second, time: 10, text: "This box")
        try review.send(batchID: Self.batch, at: Self.now)
        try review.addComment(id: Self.queued, time: 15, text: "Later")
        return review
    }

    // MARK: - ack

    @Test("an acknowledgement moves the batch's sent comments to acknowledged, and leaves every other comment")
    func acknowledge() throws {
        var review = try sent()
        try review.setStatus(Self.second, .working)

        let batch = try review.acknowledge(Self.batch, messageID: message(1), at: Self.now)

        #expect(review.comments.map(\.state) == [.acknowledged, .working, .queued])
        #expect(batch.messages.isEmpty)
        #expect(review.batch(Self.batch) == batch)
    }

    @Test("an acknowledgement's words are a message for the full batch, by the agent")
    func acknowledgeWithText() throws {
        var review = try sent()
        let batch = try review.acknowledge(Self.batch, text: "  On it\n", messageID: message(1), at: Self.now)
        #expect(batch.messages == [ThreadMessage(id: message(1), author: .agent, kind: .message, text: "On it", at: Self.now)])
        // Words that are only space are no message.
        try review.acknowledge(Self.batch, text: " ", messageID: message(2), at: Self.now)
        #expect(review.batch(Self.batch)?.messages.count == 1)
    }

    @Test("an acknowledgement of a batch the review doesn't have is refused")
    func acknowledgeUnknown() throws {
        var review = try sent()
        let before = review
        let other = ItemID("b-00000009")!
        #expect(throws: ReviewRefusal.unknownBatch("b-00000009")) { try review.acknowledge(other, messageID: message(1), at: Self.now) }
        #expect(review == before)
    }

    // MARK: - status

    @Test("a status moves a comment forward, and may skip a state", arguments: [
        ([CommentState.working], CommentState.working),
        ([.working, .done], .done),
        ([.done], .done),
        ([.failed], .failed),
        ([.working, .failed], .failed),
        ([.working, .working], .working),
    ])
    func status(moves: [CommentState], end: CommentState) throws {
        var review = try sent()
        for state in moves { try review.setStatus(Self.first, state) }
        #expect(review.comment(Self.first)?.state == end)
        #expect(review.comment(Self.second)?.state == .sent)
    }

    @Test("a status never moves a comment back, and done and failed are final", arguments: [
        (CommentState.done, CommentState.working), (.done, .failed), (.failed, .done), (.failed, .working),
        (.working, .acknowledged), (.working, .sent), (.working, .queued),
    ])
    func statusBackwards(from: CommentState, to: CommentState) throws {
        var review = try sent()
        try review.setStatus(Self.first, from)
        let before = review
        #expect(throws: ReviewRefusal.illegalMove(Self.first, from: from, to: to)) { try review.setStatus(Self.first, to) }
        #expect(review == before)
    }

    @Test("a status on a comment that isn't there, or wasn't sent yet, is refused")
    func statusRefused() throws {
        var review = try sent()
        #expect(throws: ReviewRefusal.unknownComment("c-00000009")) { try review.setStatus(ItemID("c-00000009")!, .done) }
        #expect(throws: ReviewRefusal.notSent(Self.queued)) { try review.setStatus(Self.queued, .working) }
        #expect(ReviewRefusal.illegalMove(Self.first, from: .done, to: .working).line.hasPrefix("c-00000001 is done and can't move to working"))
    }

    @Test("a batch is finished once each of its comments is done or failed")
    func finishes() throws {
        var review = try sent()
        try review.setStatus(Self.first, .done)
        #expect(!review.isFinished(Self.batch))
        try review.setStatus(Self.second, .failed)
        #expect(review.isFinished(Self.batch))
    }

    // MARK: - reply

    @Test("a reply to a comment is the agent's message in that comment's thread")
    func replyToAComment() throws {
        var review = try sent()
        let reply = try review.reply(to: Self.first, text: " Slowed it down ", messageID: message(1), at: Self.now)
        #expect(reply == ThreadMessage(id: message(1), author: .agent, kind: .message, text: "Slowed it down", at: Self.now))
        #expect(review.comment(Self.first)?.thread == [reply])
        #expect(review.comment(Self.second)?.thread == [])
        #expect(review.batch(Self.batch)?.messages == [])
        // A reply changes no state.
        #expect(review.comment(Self.first)?.state == .sent)
    }

    @Test("a reply to a batch id is a message for the full batch")
    func replyToABatch() throws {
        var review = try sent()
        let reply = try review.reply(to: Self.batch, text: "All done in one commit", messageID: message(1), at: Self.now)
        #expect(review.batch(Self.batch)?.messages == [reply])
        #expect(review.comments.allSatisfy { $0.thread.isEmpty })
    }

    @Test("a reply with no words, or to something the review doesn't have, is refused")
    func replyRefused() throws {
        var review = try sent()
        let before = review
        #expect(throws: ReviewRefusal.emptyMessage) { try review.reply(to: Self.first, text: " \n", messageID: message(1), at: Self.now) }
        #expect(throws: ReviewRefusal.unknownComment("c-00000009")) {
            try review.reply(to: ItemID("c-00000009")!, text: "Hello", messageID: message(1), at: Self.now)
        }
        #expect(throws: ReviewRefusal.unknownBatch("b-00000009")) {
            try review.reply(to: ItemID("b-00000009")!, text: "Hello", messageID: message(1), at: Self.now)
        }
        #expect(throws: ReviewRefusal.notSent(Self.queued)) {
            try review.reply(to: Self.queued, text: "Hello", messageID: message(1), at: Self.now)
        }
        #expect(review == before)
    }

    // MARK: - ask and answer

    @Test("a question is open until the person answers it, and both keep their author and kind")
    func askAndAnswer() throws {
        var review = try sent()
        let question = try review.ask(Self.first, question: "Which part?", messageID: message(1), at: Self.now)
        #expect(question == ThreadMessage(id: message(1), author: .agent, kind: .question, text: "Which part?", at: Self.now))
        #expect(review.comment(Self.first)?.openQuestion == question)

        let later = Self.now.addingTimeInterval(30)
        let answer = try review.answer(Self.first, text: " The intro ", messageID: message(2), at: later)

        #expect(answer == ThreadMessage(id: message(2), author: .person, kind: .answer, text: "The intro", at: later))
        #expect(review.comment(Self.first)?.thread == [question, answer])
        #expect(review.comment(Self.first)?.openQuestion == nil)
    }

    @Test("a comment has one open question at most; once it's answered the agent can ask again")
    func oneOpenQuestion() throws {
        var review = try sent()
        try review.ask(Self.first, question: "Which part?", messageID: message(1), at: Self.now)
        // A reply doesn't close the question.
        try review.reply(to: Self.first, text: "Meanwhile", messageID: message(2), at: Self.now)
        let before = review
        #expect(throws: ReviewRefusal.questionOpen(Self.first)) {
            try review.ask(Self.first, question: "And how?", messageID: message(3), at: Self.now)
        }
        #expect(review == before)
        // Another comment has its own question.
        try review.ask(Self.second, question: "This one?", messageID: message(3), at: Self.now)

        try review.answer(Self.first, text: "The intro", messageID: message(4), at: Self.now)
        let again = try review.ask(Self.first, question: "And how?", messageID: message(5), at: Self.now)
        #expect(review.comment(Self.first)?.openQuestion == again)
        #expect(review.comment(Self.first)?.thread.map(\.kind) == [.question, .message, .answer, .question])
    }

    @Test("an answer with no open question, with no words, or on no comment is refused")
    func answerRefused() throws {
        var review = try sent()
        #expect(throws: ReviewRefusal.noQuestion(Self.first)) { try review.answer(Self.first, text: "Yes", messageID: message(1), at: Self.now) }
        try review.reply(to: Self.first, text: "A message is no question", messageID: message(1), at: Self.now)
        #expect(throws: ReviewRefusal.noQuestion(Self.first)) { try review.answer(Self.first, text: "Yes", messageID: message(2), at: Self.now) }
        try review.ask(Self.first, question: "Which part?", messageID: message(2), at: Self.now)
        let before = review
        #expect(throws: ReviewRefusal.emptyMessage) { try review.answer(Self.first, text: " ", messageID: message(3), at: Self.now) }
        #expect(throws: ReviewRefusal.unknownComment("c-00000009")) {
            try review.answer(ItemID("c-00000009")!, text: "Yes", messageID: message(3), at: Self.now)
        }
        #expect(review == before)
        try review.answer(Self.first, text: "Yes", messageID: message(3), at: Self.now)
        #expect(throws: ReviewRefusal.noQuestion(Self.first)) { try review.answer(Self.first, text: "Again", messageID: message(4), at: Self.now) }
    }

    @Test("a question with no words, or on a comment that wasn't sent, is refused")
    func askRefused() throws {
        var review = try sent()
        let before = review
        #expect(throws: ReviewRefusal.emptyMessage) { try review.ask(Self.first, question: "", messageID: message(1), at: Self.now) }
        #expect(throws: ReviewRefusal.notSent(Self.queued)) { try review.ask(Self.queued, question: "Why?", messageID: message(1), at: Self.now) }
        #expect(review == before)
    }

    // MARK: - On disk

    @Test("threads and batch messages read back from JSON with each message's author and kind")
    func roundTrip() throws {
        var review = try sent()
        try review.acknowledge(Self.batch, text: "On it", messageID: message(1), at: Self.now)
        try review.ask(Self.first, question: "Which part?", messageID: message(2), at: Self.now)
        try review.answer(Self.first, text: "The intro", messageID: message(3), at: Self.now)
        try review.reply(to: Self.first, text: "Done", messageID: message(4), at: Self.now)

        let data = try JSONEncoder().encode(review)
        #expect(try JSONDecoder().decode(VideoReview.self, from: data) == review)

        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let thread = try #require((object["comments"] as? [[String: Any]])?.first?["thread"] as? [[String: Any]])
        #expect(thread.map { $0["author"] as? String } == ["agent", "person", "agent"])
        #expect(thread.map { $0["kind"] as? String } == ["question", "answer", "message"])
        #expect(thread.map { $0["id"] as? String } == ["m-00000002", "m-00000003", "m-00000004"])
    }

    @Test("a batch that goes back to the queue keeps its threads and messages")
    func requeueKeepsThreads() throws {
        var review = try sent()
        try review.acknowledge(Self.batch, text: "On it", messageID: message(1), at: Self.now)
        try review.reply(to: Self.first, text: "Half way", messageID: message(2), at: Self.now)
        try review.setStatus(Self.first, .working)
        review.requeue(Self.batch)
        #expect(review.comments.map(\.state) == [.sent, .sent, .queued])
        #expect(review.comment(Self.first)?.thread.count == 1)
        #expect(review.batch(Self.batch)?.messages.count == 1)
    }
}

@Suite("The outbox while the listener asks")
struct OutboxAskTests {
    static let now = Date(timeIntervalSince1970: 1_790_000_000)
    static let listener = ListenerSession(key: "listener-1", name: "Claude Code", place: "/shop")
    static let ref = BatchRef(batchID: ItemID("b-00000001")!, contentHash: "abc")

    @Test("a listener with an open ask is there for as long as it waits, and 120 s after while it has a batch")
    func openAsk() {
        var outbox = Outbox()
        outbox.enqueue(Self.ref)
        outbox.waitOpened(by: Self.listener, at: Self.now)
        _ = outbox.deliverNext(at: Self.now)
        outbox.askOpened(at: Self.now)
        #expect(outbox.presence(at: Self.now.addingTimeInterval(3600)) == .working)

        outbox.askClosed(at: Self.now.addingTimeInterval(3600))
        #expect(outbox.openAsks == 0)
        #expect(outbox.presence(at: Self.now.addingTimeInterval(3700)) == .working)
        #expect(outbox.presence(at: Self.now.addingTimeInterval(3721)) == .absent)
    }

    @Test("each listener command says the listener is alive, and a finished batch leaves it listening")
    func heardAndFinished() {
        var outbox = Outbox()
        outbox.enqueue(Self.ref)
        outbox.waitOpened(by: Self.listener, at: Self.now)
        _ = outbox.deliverNext(at: Self.now)
        #expect(outbox.presence(at: Self.now.addingTimeInterval(121)) == .absent)
        outbox.heard(at: Self.now.addingTimeInterval(121))
        #expect(outbox.presence(at: Self.now.addingTimeInterval(200)) == .working)

        outbox.finished(Self.ref)
        outbox.waitOpened(by: Self.listener, at: Self.now.addingTimeInterval(201))
        #expect(outbox.taken.isEmpty)
        #expect(outbox.presence(at: Self.now.addingTimeInterval(4000)) == .listening)
    }

    @Test("an open ask isn't kept on disk")
    func notOnDisk() throws {
        var outbox = Outbox()
        outbox.askOpened(at: Self.now)
        let read = try JSONDecoder().decode(Outbox.self, from: JSONEncoder().encode(outbox))
        #expect(read.openAsks == 0)
    }
}
