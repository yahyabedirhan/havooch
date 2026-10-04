import Foundation
import Testing
import VRReview

private let video = VideoInfo(path: "/Users/me/sample.mp4", contentHash: "abc", duration: 21.233, title: "sample")

/// A session with one comment in `state`, read from JSON as the store will
/// keep it: the way a sent comment exists before batches are built.
private func session(with state: CommentState) throws -> ReviewSession {
    let json = """
        {"video":{"path":"/Users/me/sample.mp4","contentHash":"abc","duration":21.233,"title":"sample"},
         "comments":[{"id":"c1","time":10,"text":"too fast","state":"\(state.rawValue)"}]}
        """
    return try JSONDecoder().decode(ReviewSession.self, from: Data(json.utf8))
}

private func refusal(_ body: () throws(ReviewRefusal) -> Void) -> String? {
    do throws(ReviewRefusal) {
        try body()
        return nil
    } catch {
        return error.reason
    }
}

@Suite struct CommentStateTests {
    /// Every allowed move, as `from→to`. Anything else is refused.
    private static let allowed: Set<String> = [
        "draft→queued", "queued→sent", "sent→acknowledged",
        "sent→working", "sent→done", "sent→failed",
        "acknowledged→working", "acknowledged→done", "acknowledged→failed",
        "working→done", "working→failed",
        // The requeue, the only move backward.
        "acknowledged→sent", "working→sent",
    ]

    @Test func aCommentMovesOnlyAsTheStateMachineSays() {
        for from in CommentState.allCases {
            for to in CommentState.allCases {
                let move = "\(from.rawValue)→\(to.rawValue)"
                #expect(from.canMove(to: to) == Self.allowed.contains(move), "\(move)")
            }
        }
    }

    @Test func doneAndFailedAreFinal() {
        #expect(CommentState.allCases.filter(\.isFinal) == [.done, .failed])
        for final in [CommentState.done, .failed] {
            #expect(CommentState.allCases.allSatisfy { !final.canMove(to: $0) })
        }
    }
}

@Suite struct ReviewSessionTests {
    @Test func aDraftBecomesAQueuedCommentWithItsTimeAndText() throws {
        var session = ReviewSession(video: video)

        let draft = session.draft(id: "c1", time: 10)
        #expect(draft == Comment(id: "c1", time: 10, text: "", state: .draft))
        #expect(session.queue.isEmpty)

        try session.commit("c1", text: "  too fast\n")

        #expect(session.comments == [Comment(id: "c1", time: 10, text: "too fast", state: .queued)])
        #expect(session.queue.map(\.id) == ["c1"])
        #expect(session.comment("c1")?.text == "too fast")
    }

    @Test func commentsAndTheQueueAreInTimeOrderHoweverTheyWereMade() throws {
        var session = ReviewSession(video: video)
        for (id, time) in [("c1", 15.0), ("c2", 3), ("c3", 10), ("c4", 10), ("c5", 0)] {
            session.draft(id: id, time: time)
            if id != "c4" { try session.commit(id, text: id) }
        }

        #expect(session.comments.map(\.id) == ["c5", "c2", "c3", "c4", "c1"])
        // The draft isn't in the queue.
        #expect(session.queue.map(\.id) == ["c5", "c2", "c3", "c1"])
    }

    @Test func aCommentNeedsItsText() {
        var session = ReviewSession(video: video)
        session.draft(id: "c1", time: 10)

        #expect(refusal { () throws(ReviewRefusal) in try session.commit("c1", text: " \n ") } == "a comment needs its text")
        #expect(session.comment("c1")?.state == .draft)
    }

    @Test func aDraftIsDiscardedAndAQueuedCommentIsNot() throws {
        var session = ReviewSession(video: video)
        session.draft(id: "c1", time: 10)
        session.draft(id: "c2", time: 12)
        try session.commit("c2", text: "keep")

        try session.discard("c1")

        #expect(session.comments.map(\.id) == ["c2"])
        #expect(refusal { () throws(ReviewRefusal) in try session.discard("c2") } == "c2 isn't a draft; it's queued")
        #expect(refusal { () throws(ReviewRefusal) in try session.commit("c2", text: "again") } == "c2 isn't a draft; it's queued")
    }

    @Test func aQueuedCommentIsEdited() throws {
        var session = ReviewSession(video: video)
        session.draft(id: "c1", time: 10)
        try session.commit("c1", text: "too fast")

        try session.edit("c1", text: "too fast here ")

        #expect(session.comments == [Comment(id: "c1", time: 10, text: "too fast here", state: .queued)])
        #expect(refusal { () throws(ReviewRefusal) in try session.edit("c1", text: "") } == "a comment needs its text")
        #expect(session.comment("c1")?.text == "too fast here")
    }

    @Test func aQueuedCommentIsDeletedFromTheReviewAndTheQueue() throws {
        var session = ReviewSession(video: video)
        session.draft(id: "c1", time: 10)
        try session.commit("c1", text: "one")
        session.draft(id: "c2", time: 5)
        try session.commit("c2", text: "two")

        try session.delete("c1")

        #expect(session.comments.map(\.id) == ["c2"])
        #expect(session.queue.map(\.id) == ["c2"])
    }

    @Test(arguments: [CommentState.sent, .acknowledged, .working, .done, .failed])
    func aSentCommentIsNeitherEditedNorDeleted(state: CommentState) throws {
        var session = try session(with: state)
        let before = session

        #expect(refusal { () throws(ReviewRefusal) in try session.edit("c1", text: "other") } == "c1 was sent; it can't be edited")
        #expect(refusal { () throws(ReviewRefusal) in try session.delete("c1") } == "c1 was sent; it can't be deleted")
        #expect(session == before)
        #expect(session.queue.isEmpty)
    }

    @Test func aDraftIsNeitherEditedNorDeleted() {
        var session = ReviewSession(video: video)
        session.draft(id: "c1", time: 10)

        #expect(refusal { () throws(ReviewRefusal) in try session.edit("c1", text: "x") } == "c1 is still being written; it can't be edited")
        #expect(refusal { () throws(ReviewRefusal) in try session.delete("c1") } == "c1 is still being written; it can't be deleted")
        #expect(session.comments.map(\.id) == ["c1"])
    }

    @Test func aCommentThatIsNotThereIsNamed() {
        var session = ReviewSession(video: video)
        let missing = "there's no comment c9"

        #expect(refusal { () throws(ReviewRefusal) in try session.commit("c9", text: "x") } == missing)
        #expect(refusal { () throws(ReviewRefusal) in try session.discard("c9") } == missing)
        #expect(refusal { () throws(ReviewRefusal) in try session.edit("c9", text: "x") } == missing)
        #expect(refusal { () throws(ReviewRefusal) in try session.delete("c9") } == missing)
    }

    @Test func theNoteIsKeptWithoutTheWhiteSpaceAroundItAndAnEmptyOneTakesItAway() throws {
        var session = try session(with: .queued)
        // A review kept before a note was written has none.
        #expect(session.note == "")

        session.setNote("  Mind the pacing.\n")
        #expect(session.note == "Mind the pacing.")

        session.setNote(" \n")
        #expect(session.note == "")
    }

    @Test func aSessionReadsBackAsItWasSaved() throws {
        var session = ReviewSession(video: video)
        session.setNote("Mind the pacing.")
        session.draft(id: "c1", time: 10)
        try session.commit("c1", text: "too fast")
        _ = try session.send(batchID: "b1", at: Date(timeIntervalSince1970: 1_000))
        session.draft(id: "c2", time: 12)

        let data = try JSONEncoder().encode(session)

        #expect(try JSONDecoder().decode(ReviewSession.self, from: data) == session)
    }

    @Test func sendingMakesOneBatchOfEveryQueuedComment() throws {
        var session = ReviewSession(video: video)
        for (id, time) in [("c1", 15.0), ("c2", 3), ("c3", 10)] {
            session.draft(id: id, time: time)
            if id != "c3" { try session.commit(id, text: id) }
        }
        let sentAt = Date(timeIntervalSince1970: 1_000)

        let batch = try session.send(batchID: "b1", at: sentAt)

        // In time order; the draft isn't sent.
        #expect(batch == Batch(id: "b1", sentAt: sentAt, commentIDs: ["c2", "c1"]))
        #expect(session.batches == [batch])
        #expect(session.batch("b1") == batch)
        #expect(session.comments.map(\.state) == [.sent, .draft, .sent])
        #expect(session.comments.map(\.batchID) == ["b1", nil, "b1"])
        #expect(session.queue.isEmpty)
        #expect(!session.isFinished("b1"))
    }

    @Test func sendingWithNothingQueuedIsRefused() {
        var session = ReviewSession(video: video)
        session.draft(id: "c1", time: 10)

        #expect(refusal { () throws(ReviewRefusal) in _ = try session.send(batchID: "b1", at: Date()) }
            == "there's nothing to send: no comment is queued")
        #expect(session.batches.isEmpty)
    }

    @Test func aSecondSendTakesOnlyWhatWasQueuedSince() throws {
        var session = ReviewSession(video: video)
        session.draft(id: "c1", time: 10)
        try session.commit("c1", text: "one")
        _ = try session.send(batchID: "b1", at: Date())
        session.draft(id: "c2", time: 5)
        try session.commit("c2", text: "two")

        let second = try session.send(batchID: "b2", at: Date())

        #expect(second.commentIDs == ["c2"])
        #expect(session.comment("c1")?.batchID == "b1")
        #expect(session.comment("c2")?.batchID == "b2")
    }

    /// A batch whose comments a listener had moved on, as the store keeps it.
    private func taken(_ states: [CommentState]) throws -> ReviewSession {
        let comments = states.enumerated().map { index, state in
            #"{"id":"c\#(index + 1)","time":\#(index),"text":"x","state":"\#(state.rawValue)","batchID":"b1"}"#
        }
        let json = """
            {"video":{"path":"/Users/me/sample.mp4","contentHash":"abc","duration":21.233,"title":"sample"},
             "comments":[\(comments.joined(separator: ","))],
             "batches":[{"id":"b1","sentAt":0,"commentIDs":["c1"]}]}
            """
        return try JSONDecoder().decode(ReviewSession.self, from: Data(json.utf8))
    }

    @Test func aRequeuePutsUnfinishedCommentsBackToSentAndLeavesTheFinishedOnes() throws {
        var session = try taken([.sent, .acknowledged, .working, .done, .failed])

        session.requeue("b1")

        #expect(session.comments.map(\.state) == [.sent, .sent, .sent, .done, .failed])
    }

    @Test func aBatchIsFinishedOnceEveryCommentIsDoneOrFailed() throws {
        #expect(try taken([.done, .failed]).isFinished("b1"))
        #expect(try !taken([.done, .working]).isFinished("b1"))
    }
}
