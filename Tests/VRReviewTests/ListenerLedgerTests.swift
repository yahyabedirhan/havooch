import Foundation
import Testing
import VRReview

/// Which batch goes to whom, at times the test sets.
@Suite struct ListenerLedgerTests {
    static let video = "7f3a9c21" + String(repeating: "0", count: 56)
    static let first = (key: "L1", name: "Claude Code", place: "/work")
    static let second = (key: "L2", name: "codex", place: "/blog")
    let b1 = BatchID(rawValue: "7f3a9c21-b1")
    let b2 = BatchID(rawValue: "7f3a9c21-b2")

    private func at(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: seconds)
    }

    /// A ledger with `b1` sent at 0 and `b2` at 5.
    private func ledger() -> ListenerLedger {
        var ledger = ListenerLedger()
        ledger.enqueue(b1, video: Self.video, sentAt: at(0))
        ledger.enqueue(b2, video: Self.video, sentAt: at(5))
        return ledger
    }

    // MARK: - Deliveries

    @Test func aSentBatchIsPendingAndTheOldestGoesFirst() {
        var ledger = ledger()
        // Sending the same batch twice keeps one delivery.
        ledger.enqueue(b1, video: Self.video, sentAt: at(9))

        #expect(ledger.deliveries.map(\.batch) == [b1, b2])
        #expect(ledger.next()?.batch == b1)
        #expect(ledger.standing(of: b1) == .pending)
        #expect(ledger.session == nil)
    }

    @Test func aBatchWhoseReplyIsBeingWrittenIsNotTheNextOne() {
        let ledger = ledger()

        #expect(ledger.next(except: [b1])?.batch == b2)
        #expect(ledger.next(except: [b1, b2]) == nil)
    }

    @Test func aDeliveredBatchIsTakenByItsListenerAndIsNotHandedOutAgain() {
        var ledger = ledger()
        ledger.attach(Self.first, now: at(10))

        ledger.delivered(b1, to: "L1", context: nil, now: at(11))

        #expect(ledger.standing(of: b1) == .taken)
        #expect(ledger.deliveries.first?.takenBy == "L1")
        #expect(ledger.deliveries.first?.takenAt == at(11))
        #expect(ledger.next()?.batch == b2)
        #expect(ledger.hasTaken)
    }

    @Test func aFinishedBatchLeavesTheLedger() {
        var ledger = ledger()
        ledger.attach(Self.first, now: at(10))
        ledger.delivered(b1, to: "L1", context: nil, now: at(11))

        ledger.finish(b1)

        #expect(ledger.standing(of: b1) == .finished)
        #expect(ledger.deliveries.map(\.batch) == [b2])
        #expect(!ledger.hasTaken)
    }

    // MARK: - The session

    @Test func theFirstListenerCommandStartsTheSessionAndTheSameKeyOnlyNotesTheTime() {
        var ledger = ledger()

        let started = ledger.attach(Self.first, now: at(10))
        ledger.delivered(b1, to: "L1", context: nil, now: at(11))
        let again = ledger.attach(Self.first, now: at(40))

        #expect(started.isEmpty)
        // The same listener calling again gets nothing twice.
        #expect(again.isEmpty)
        #expect(ledger.standing(of: b1) == .taken)
        #expect(ledger.session?.key == "L1")
        #expect(ledger.session?.name == "Claude Code")
        #expect(ledger.session?.place == "/work")
        #expect(ledger.session?.firstSeen == at(10))
        #expect(ledger.session?.lastSeen == at(40))
    }

    @Test func aListenerCommandFromAnotherKeyStartsANewSessionAndRequeuesWhatTheOldOneTook() {
        var ledger = ledger()
        ledger.attach(Self.first, now: at(10))
        ledger.delivered(b1, to: "L1", context: "the context", now: at(11))

        let requeued = ledger.attach(Self.second, now: at(60))

        #expect(requeued.map(\.batch) == [b1])
        #expect(ledger.standing(of: b1) == .pending)
        #expect(ledger.deliveries.first?.takenBy == nil)
        // The oldest first again, before the one that was never taken.
        #expect(ledger.next()?.batch == b1)
        // A new session remembers nothing of the context.
        #expect(ledger.session?.key == "L2")
        #expect(ledger.session?.place == "/blog")
        #expect(ledger.session?.firstSeen == at(60))
        #expect(ledger.session?.contextSent == [:])
    }

    @Test func aReplyThatReachedAListenerWhoIsNoLongerTheSessionTakesNothing() {
        var ledger = ledger()
        ledger.attach(Self.first, now: at(10))
        // Another listener started while the reply to the first was written.
        ledger.attach(Self.second, now: at(11))

        ledger.delivered(b1, to: "L1", context: nil, now: at(12))

        #expect(ledger.standing(of: b1) == .pending)
        #expect(!ledger.hasTaken)
    }

    @Test func theContextThatWentWithABatchIsRememberedForItsVideo() {
        var ledger = ledger()
        ledger.attach(Self.first, now: at(10))

        ledger.delivered(b1, to: "L1", context: "# Context", now: at(11))
        ledger.delivered(b2, to: "L1", context: nil, now: at(12))

        #expect(ledger.session?.contextSent == [Self.video: "# Context"])
    }

    // MARK: - Context once per session

    /// One batch going to a listener, with the context text there is then.
    struct Step: Sendable, CustomTestStringConvertible {
        var listener = "L1"
        var video = ListenerLedgerTests.video
        var text: String
        /// Whether the reply carrying the batch reached the listener.
        var written = true
        /// What the payload's `context` is.
        var sends: String?

        var testDescription: String { "\(listener) gets \(sends ?? "null") of \"\(text)\"" }
    }

    static let other = "c0ffee00" + String(repeating: "1", count: 56)

    @Test(arguments: [
        // The first batch of a session has the text, the next has null.
        [Step(text: "v1", sends: "v1"), Step(text: "v1", sends: nil), Step(text: "v1", sends: nil)],
        // A changed text is sent again, once.
        [Step(text: "v1", sends: "v1"), Step(text: "v2", sends: "v2"), Step(text: "v2", sends: nil)],
        // A new session gets it again, and the session before, coming back, is new as well.
        [
            Step(text: "v1", sends: "v1"), Step(listener: "L2", text: "v1", sends: "v1"),
            Step(listener: "L2", text: "v1", sends: nil), Step(text: "v1", sends: "v1"),
        ],
        // Each video has its own: one's context says nothing of another's.
        [
            Step(text: "v1", sends: "v1"), Step(video: other, text: "v1", sends: "v1"),
            Step(text: "v1", sends: nil), Step(video: other, text: "other v2", sends: "other v2"), Step(text: "v1", sends: nil),
        ],
        // No context is null, and one that comes later is sent then.
        [Step(text: "", sends: nil), Step(text: "v1", sends: "v1"), Step(text: "", sends: nil), Step(text: "v1", sends: nil)],
        // A reply that never reached the listener is remembered as nothing.
        [Step(text: "v1", written: false, sends: "v1"), Step(text: "v1", sends: "v1"), Step(text: "v1", sends: nil)],
    ] as [[Step]])
    func theContextGoesOutWithTheFirstBatchOfASessionAndAgainOnlyWhenItsTextChanged(steps: [Step]) {
        var ledger = ListenerLedger()
        for (index, step) in steps.enumerated() {
            let batch = BatchID(rawValue: "\(step.video.prefix(8))-b\(index + 1)")
            ledger.enqueue(batch, video: step.video, sentAt: at(Double(index)))
            ledger.attach((key: step.listener, name: "Claude Code", place: "/work"), now: at(Double(index)))

            let context = ledger.contextToSend(step.text, video: step.video)

            #expect(context == step.sends, "step \(index + 1)")
            if step.written { ledger.delivered(batch, to: step.listener, context: context, now: at(Double(index))) }
            // Finished, so a later session has nothing to take over.
            ledger.finish(batch)
        }
    }

    @Test func withNoListenerSessionThereIsNoContextToSend() {
        #expect(ListenerLedger().contextToSend("v1", video: Self.video) == nil)
    }

    // MARK: - Presence

    @Test func presenceIsDerivedFromTheOpenWaitTheTakenBatchAndTheLastCommand() {
        var ledger = ledger()
        // Nobody ever listened.
        #expect(ledger.presence(waitOpen: false, now: at(0)) == .absent)

        ledger.attach(Self.first, now: at(10))
        #expect(ledger.presence(waitOpen: true, now: at(10)) == .listening)
        // The wait closed with nothing taken.
        #expect(ledger.presence(waitOpen: false, now: at(10)) == .absent)

        ledger.delivered(b1, to: "L1", context: nil, now: at(20))
        #expect(ledger.presence(waitOpen: false, now: at(20)) == .working)
        #expect(ledger.presence(waitOpen: true, now: at(500)) == .working)
        #expect(ledger.presence(waitOpen: false, now: at(139.9)) == .working)
        // 120 s after its last command, a listener with no wait open is gone.
        #expect(ledger.presence(waitOpen: false, now: at(140)) == .absent)

        ledger.attach(Self.first, now: at(200))
        #expect(ledger.presence(waitOpen: false, now: at(300)) == .working)

        ledger.finish(b1)
        #expect(ledger.presence(waitOpen: false, now: at(300)) == .absent)
        #expect(ledger.presence(waitOpen: true, now: at(300)) == .listening)
    }

    @Test func theLedgerReadsBackAsItWasWritten() throws {
        var ledger = ledger()
        ledger.attach(Self.first, now: at(10))
        ledger.delivered(b1, to: "L1", context: "# Context", now: at(11))

        let back = try JSONDecoder().decode(ListenerLedger.self, from: JSONEncoder().encode(ledger))

        #expect(back == ledger)
    }
}
