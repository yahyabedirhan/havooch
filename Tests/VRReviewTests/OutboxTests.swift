import Foundation
import Testing
import VRReview

private func at(_ seconds: TimeInterval) -> Date {
    Date(timeIntervalSince1970: seconds)
}

@Suite struct OutboxTests {
    @Test func aBatchSentWithNoListenerWaitsForTheNextWait() {
        var outbox = Outbox()
        outbox.post(batchID: "b1", videoHash: "abc")

        // Nobody listens: nothing is taken.
        #expect(outbox.take(at: at(0)) == nil)
        #expect(outbox.parcel("b1")?.delivery == .pending)

        outbox.arrive(key: "one", name: "Claude Code", at: at(10))

        #expect(outbox.take(at: at(10)) == Outbox.Parcel(batchID: "b1", videoHash: "abc", delivery: .taken(by: "one", at: at(10))))
        #expect(outbox.take(at: at(11)) == nil)
    }

    @Test func batchesAreTakenOldestFirst() {
        var outbox = Outbox()
        outbox.post(batchID: "b1", videoHash: "abc")
        outbox.post(batchID: "b2", videoHash: "def")
        outbox.arrive(key: "one", name: "Claude Code", at: at(0))

        #expect(outbox.take(at: at(0))?.batchID == "b1")
        #expect(outbox.take(at: at(0))?.batchID == "b2")
    }

    @Test func aListenerThatStartedAgainGetsTheBatchItsEarlierSessionTookAndDidNotFinish() {
        var outbox = Outbox()
        outbox.post(batchID: "b1", videoHash: "abc")
        outbox.post(batchID: "b2", videoHash: "abc")
        outbox.arrive(key: "one", name: "Claude Code", at: at(0))
        _ = outbox.take(at: at(0))
        _ = outbox.take(at: at(0))
        outbox.leave(key: "one", at: at(1), delivered: true)
        // b2 was finished; b1 wasn't.
        outbox.finish("b2")

        let requeued = outbox.arrive(key: "two", name: "Claude Code", at: at(60))

        #expect(requeued.map(\.batchID) == ["b1"])
        #expect(outbox.take(at: at(60)) == Outbox.Parcel(batchID: "b1", videoHash: "abc", delivery: .taken(by: "two", at: at(60))))
    }

    @Test func afterAnAppRestartEveryTakenBatchIsPendingForTheNextWaitOfTheSameListenerToo() {
        var kept = Outbox()
        kept.post(batchID: "b1", videoHash: "abc")
        kept.post(batchID: "b2", videoHash: "abc")
        kept.arrive(key: "one", name: "Claude Code", at: at(0))
        _ = kept.take(at: at(0))

        // What the store kept: the parcels, not the listener.
        var outbox = Outbox(parcels: kept.parcels)
        let requeued = outbox.restart()

        #expect(requeued.map(\.batchID) == ["b1"])
        #expect(outbox.parcels.map(\.delivery) == [.pending, .pending])
        #expect(outbox.presence(at: at(1)) == .absent)
        // The listener that had it runs `wait` again, and gets it again.
        #expect(outbox.arrive(key: "one", name: "Claude Code", at: at(60)).isEmpty)
        #expect(outbox.take(at: at(60))?.batchID == "b1")
        // Nothing counts as already sent to it.
        #expect(outbox.context(for: "abc", text: "the context") == "the context")
    }

    @Test func theSameListenerWaitingAgainGetsNoSecondCopyOfItsBatch() {
        var outbox = Outbox()
        outbox.post(batchID: "b1", videoHash: "abc")
        outbox.arrive(key: "one", name: "Claude Code", at: at(0))
        _ = outbox.take(at: at(0))
        outbox.leave(key: "one", at: at(1), delivered: true)

        #expect(outbox.arrive(key: "one", name: "Claude Code", at: at(5)).isEmpty)
        #expect(outbox.take(at: at(5)) == nil)
    }

    @Test func aBatchThatCouldNotBeWrittenIsPendingAgain() {
        var outbox = Outbox()
        outbox.post(batchID: "b1", videoHash: "abc")
        outbox.arrive(key: "one", name: "Claude Code", at: at(0))
        _ = outbox.take(at: at(0))

        outbox.undelivered("b1")
        outbox.leave(key: "one", at: at(1), delivered: false)

        #expect(outbox.parcel("b1")?.delivery == .pending)
        #expect(outbox.presence(at: at(1)) == .absent)
    }

    @Test func presenceFollowsTheWaitAndTheWork() {
        var outbox = Outbox()
        #expect(outbox.presence(at: at(0)) == .absent)

        outbox.arrive(key: "one", name: "Claude Code", at: at(0))
        #expect(outbox.presence(at: at(0)) == .listening)
        #expect(outbox.listener == Outbox.Listener(key: "one", name: "Claude Code"))

        // The wait ran out with no batch: nobody listens.
        outbox.leave(key: "one", at: at(5), delivered: false)
        #expect(outbox.presence(at: at(5)) == .absent)

        outbox.post(batchID: "b1", videoHash: "abc")
        outbox.arrive(key: "one", name: "Claude Code", at: at(10))
        _ = outbox.take(at: at(10))
        #expect(outbox.presence(at: at(10)) == .working)

        // The wait closed with its batch: the listener reads it, then waits
        // again. It counts as there for a while.
        outbox.leave(key: "one", at: at(11), delivered: true)
        #expect(outbox.presence(at: at(40)) == .working)
        #expect(outbox.presence(at: at(41)) == .absent)

        outbox.arrive(key: "one", name: "Claude Code", at: at(50))
        #expect(outbox.presence(at: at(50)) == .working)
        outbox.finish("b1")
        #expect(outbox.presence(at: at(51)) == .listening)
    }

    @Test func twoOpenWaitsOfOneListenerBothCount() {
        var outbox = Outbox()
        outbox.arrive(key: "one", name: "Claude Code", at: at(0))
        outbox.arrive(key: "one", name: "Claude Code", at: at(1))

        outbox.leave(key: "one", at: at(2), delivered: false)
        #expect(outbox.presence(at: at(2)) == .listening)
        outbox.leave(key: "one", at: at(3), delivered: false)
        #expect(outbox.presence(at: at(3)) == .absent)
    }

    @Test func aWaitOfAnEarlierListenerClosingChangesNothing() {
        var outbox = Outbox()
        outbox.arrive(key: "one", name: "Claude Code", at: at(0))
        outbox.arrive(key: "two", name: "Codex", at: at(1))

        outbox.leave(key: "one", at: at(2), delivered: true)

        #expect(outbox.presence(at: at(2)) == .listening)
        outbox.leave(key: "two", at: at(3), delivered: false)
        #expect(outbox.presence(at: at(3)) == .absent)
    }

    @Test func theContextGoesOncePerListenerSessionAndAgainWhenItChanged() {
        var outbox = Outbox()
        outbox.arrive(key: "one", name: "Claude Code", at: at(0))

        #expect(outbox.context(for: "abc", text: "about the shop") == "about the shop")
        #expect(outbox.context(for: "abc", text: "about the shop") == nil)
        // Another video's context is its own.
        #expect(outbox.context(for: "def", text: "about the shop") == "about the shop")
        #expect(outbox.context(for: "abc", text: "about the new shop") == "about the new shop")
        #expect(outbox.context(for: "abc", text: nil) == nil)
        #expect(outbox.context(for: "abc", text: "") == nil)

        // The same session waiting again already has it; a new one doesn't.
        outbox.arrive(key: "one", name: "Claude Code", at: at(5))
        #expect(outbox.context(for: "abc", text: "about the new shop") == nil)
        outbox.arrive(key: "two", name: "Claude Code", at: at(10))
        #expect(outbox.context(for: "abc", text: "about the new shop") == "about the new shop")
    }

    @Test func aBatchThatCouldNotBeWrittenTakesItsContextBackToo() {
        var outbox = Outbox()
        outbox.post(batchID: "b1", videoHash: "abc")
        outbox.arrive(key: "one", name: "Claude Code", at: at(0))
        _ = outbox.take(at: at(0))
        #expect(outbox.context(for: "abc", text: "about the shop") == "about the shop")

        outbox.undelivered("b1")

        #expect(outbox.context(for: "abc", text: "about the shop") == "about the shop")
    }
}

@Suite struct BatchPayloadTests {
    private func review() throws -> (ReviewSession, Batch) {
        var session = ReviewSession(video: VideoInfo(path: "/Users/me/sample.mp4", contentHash: "abc", duration: 21.233, title: "sample"))
        session.draft(id: "c1", time: 10)
        try session.commit("c1", text: "too fast")
        session.draft(id: "c2", time: 4.5, region: try Region(x: 0.1, y: 0.2, w: 0.3, h: 0.25))
        try session.commit("c2", text: "this button")
        let batch = try session.send(batchID: "b1", at: Date(timeIntervalSince1970: 1_759_579_200))
        // Queued after the batch: not in its payload.
        session.draft(id: "c3", time: 1)
        try session.commit("c3", text: "later")
        return (session, batch)
    }

    @Test func thePayloadIsTheSpecsObjectWithEveryKey() throws {
        let (session, batch) = try review()

        let payload = BatchPayload(
            batch: batch,
            session: session,
            context: nil,
            keyframePath: { "/support/frames/\($0.id).png" },
            cropPath: { "/support/crops/\($0.id).png" },
            transcript: { $0.id == "c1" ? [BatchPayload.Line(start: 6, end: 14.5, text: "Welcome.")] : [] }
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        #expect(String(decoding: try encoder.encode(payload), as: UTF8.self) == """
            {"batch":{"id":"b1","sentAt":"2025-10-04T12:00:00Z"},\
            "comments":[\
            {"cropPath":"/support/crops/c2.png","id":"c2","keyframePath":"/support/frames/c2.png",\
            "region":{"h":0.25,"w":0.3,"x":0.1,"y":0.2},"text":"this button","time":4.5,"transcript":[]},\
            {"cropPath":null,"id":"c1","keyframePath":"/support/frames/c1.png",\
            "region":null,"text":"too fast","time":10,"transcript":[{"end":14.5,"start":6,"text":"Welcome."}]}],\
            "context":null,\
            "video":{"contentHash":"abc","duration":21.233,"path":"/Users/me/sample.mp4","title":"sample"}}
            """)
        #expect(try JSONDecoder().decode(BatchPayload.self, from: try encoder.encode(payload)) == payload)
    }

    @Test func aCommentWhoseImagesAreNotOnDiskHasNullPathsAndTheContextIsItsText() throws {
        let (session, batch) = try review()

        let payload = BatchPayload(
            batch: batch, session: session, context: "about the shop",
            keyframePath: { _ in nil }, cropPath: { _ in nil }, transcript: { _ in [] }
        )

        #expect(payload.context == "about the shop")
        #expect(payload.comments.map(\.id) == ["c2", "c1"])
        #expect(payload.comments.allSatisfy { $0.keyframePath == nil && $0.cropPath == nil })
    }
}
