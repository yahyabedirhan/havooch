import Foundation
import ReviewCore
import Testing

@Suite("The message state machine and a thread's state")
struct MessageStateTests {
    @Test("the states are queued, sent, acknowledged, working, done and failed: no draft")
    func states() {
        #expect(MessageState.allCases == [.queued, .sent, .acknowledged, .working, .done, .failed])
        #expect(MessageState(rawValue: "draft") == nil)
    }

    @Test("a state moves forward only, may skip, and done and failed are final", arguments: [
        (MessageState.queued, MessageState.sent, true), (.sent, .acknowledged, true), (.sent, .working, true),
        (.acknowledged, .done, true), (.working, .failed, true), (.working, .acknowledged, false),
        (.sent, .queued, false), (.done, .failed, false), (.failed, .working, false), (.working, .working, false),
    ])
    func moves(from: MessageState, to: MessageState, legal: Bool) {
        #expect(from.canMove(to: to) == legal)
    }

    @Test("only a queued message is editable")
    func editable() {
        #expect(MessageState.allCases.filter(\.isEditable) == [.queued])
        #expect(MessageState.allCases.filter(\.isOpen) == [.queued, .sent, .acknowledged, .working])
    }

    /// Three messages on thread #1, sent together.
    private func sentThree() throws -> Review {
        var review = newReview()
        for text in ["a", "b", "c"] { try review.write(text: text, at: 10, now: now) }
        try review.send(at: now)
        return review
    }

    @Test("a thread's state is that of its latest open person message")
    func latestOpen() throws {
        var review = try sentThree()
        try review.setState(message(1), .working)
        try review.setState(message(3), .done)
        // m-2 is the latest open one, still sent.
        #expect(review.thread(thread(1))?.state == .sent)
        try review.setState(message(2), .working)
        #expect(review.thread(thread(1))?.state == .working)
    }

    @Test("with no open person message, a thread's state is that of its latest person message")
    func noneOpen() throws {
        var review = try sentThree()
        try review.setState(message(1), .done)
        try review.setState(message(2), .done)
        try review.setState(message(3), .failed)
        #expect(review.thread(thread(1))?.state == .failed)
    }

    @Test("agent messages and answers don't count: General with only agent messages has no state")
    func agentOnly() throws {
        var review = try sentThree()
        try review.reply(on: thread(0), text: "On it", now: now)
        try review.reply(on: thread(1), text: "Looking", now: now)
        #expect(review.general.state == nil)
        #expect(review.thread(thread(1))?.state == .sent)
    }

    @Test("a new message on a finished thread makes it active again")
    func reopen() throws {
        var review = try sentThree()
        for number in 1...3 { try review.setState(message(number), .done) }
        #expect(review.thread(thread(1))?.state == .done)
        try review.write(text: "One more thing", at: nil, to: thread(1), now: now)
        #expect(review.thread(thread(1))?.state == .queued)
    }
}

@Suite("The listener's answers on a review")
struct ListenerAnswerTests {
    /// Two messages on #1 and one on #2, sent together, and one queued on #1.
    private func sent() throws -> Review {
        var review = newReview()
        try review.write(text: "Too fast", at: 5, now: now)
        try review.write(text: "This box", at: 5, now: now)
        try review.write(text: "Other frame", at: 10, now: now)
        try review.send(at: now)
        try review.write(text: "Later", at: nil, to: thread(1), now: now)
        return review
    }

    @Test("an acknowledgement moves the send's sent messages to acknowledged, and leaves every other one")
    func acknowledge() throws {
        var review = try sent()
        try review.setState(message(2), .working)
        let acknowledged = try review.acknowledge(send(1), now: now)
        #expect(acknowledged.id == send(1))
        #expect(review.thread(thread(1))?.messages.map(\.state) == [.acknowledged, .working, .queued])
        #expect(review.thread(thread(2))?.messages.map(\.state) == [.acknowledged])
        #expect(review.general.messages.isEmpty)
    }

    @Test("an acknowledgement's words are the agent's message on General")
    func acknowledgeWords() throws {
        var review = try sent()
        try review.acknowledge(send(1), text: "  On it\n", now: now)
        #expect(review.general.messages.map(\.text) == ["On it"])
        #expect(review.general.messages.first?.author == .agent)
        #expect(review.general.messages.first?.state == nil)
        try review.acknowledge(send(1), text: " ", now: now)
        #expect(review.general.messages.count == 1)
        #expect(throws: ReviewRefusal.unknownID("s-f92cbb2a-9")) { try review.acknowledge(send(9), now: now) }
    }

    @Test("a status moves a sent message forward; the same state again changes nothing")
    func status() throws {
        var review = try sent()
        #expect(try review.setState(message(1), .working).state == .working)
        #expect(try review.setState(message(1), .working).state == .working)
        #expect(try review.setState(message(1), .done).state == .done)
        #expect(throws: ReviewRefusal.illegalMove(message(1), from: .done, to: .failed)) { try review.setState(message(1), .failed) }
        #expect(throws: ReviewRefusal.illegalMove(message(2), from: .sent, to: .queued)) { try review.setState(message(2), .queued) }
        #expect(throws: ReviewRefusal.notSent(thread(1))) { try review.setState(message(4), .working) }
        #expect(review.isFinished(send(1)) == false)
        try review.setState(message(2), .failed)
        try review.setState(message(3), .done)
        #expect(review.isFinished(send(1)))
    }

    @Test("a reply and a question need something sent on the thread; General takes them always")
    func reach() throws {
        var review = try sent()
        try review.write(text: "Unsent", at: 15, now: now)
        #expect(throws: ReviewRefusal.notSent(thread(3))) { try review.reply(on: thread(3), text: "x", now: now) }
        #expect(throws: ReviewRefusal.notSent(thread(3))) { try review.ask(on: thread(3), question: "x", now: now) }
        #expect(try review.reply(on: thread(0), text: "All good", now: now).author == .agent)
        #expect(try review.reply(on: thread(2), text: "Fixed", now: now).kind == .message)
    }

    @Test("a thread has one open question; the answer closes it, and a reply doesn't")
    func question() throws {
        var review = try sent()
        #expect(throws: ReviewRefusal.noQuestion(thread(1))) { try review.answer(thread(1), text: "x", now: now) }
        let asked = try review.ask(on: thread(1), question: "Which box?", now: now)
        #expect(asked.kind == .question)
        #expect(review.thread(thread(1))?.openQuestion == asked)
        try review.reply(on: thread(1), text: "Still looking", now: now)
        #expect(throws: ReviewRefusal.questionOpen(thread(1))) { try review.ask(on: thread(1), question: "Again?", now: now) }
        let answered = try review.answer(thread(1), text: "The left one", now: now)
        #expect(answered.author == .person && answered.kind == .answer && answered.state == nil)
        #expect(review.thread(thread(1))?.openQuestion == nil)
        // An answer is never queued.
        #expect(review.queue.map(\.id) == [message(4)])
    }

    @Test("a send requeued for a new listener returns its unfinished messages to sent")
    func requeue() throws {
        var review = try sent()
        try review.acknowledge(send(1), now: now)
        try review.setState(message(1), .done)
        try review.setState(message(2), .working)
        #expect(review.requeue(send(1)) == [message(2), message(3)])
        #expect(review.thread(thread(1))?.messages.map(\.state) == [.done, .sent, .queued])
    }
}
