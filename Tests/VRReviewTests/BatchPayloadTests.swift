import Foundation
import Testing
import VRReview

/// Sending the queue as a batch, and the JSON object `wait` prints for it.
@Suite struct BatchPayloadTests {
    static let hash = "7f3a9c21" + String(repeating: "0", count: 56)
    let now = Date(timeIntervalSince1970: 1_000)
    let sent = Date(timeIntervalSince1970: 1_791_115_200)
    let region = Region(x: 0.1, y: 0.2, w: 0.3, h: 0.2)!

    private func review() -> Review {
        Review(video: VideoInfo(contentHash: Self.hash, path: "/videos/sample.mp4", title: "sample", duration: 21.233))
    }

    /// A review with a comment at 10 s and one on a region at 4 s, both queued.
    private func queued() throws -> Review {
        var review = review()
        try review.addComment(text: "too fast", time: 10, now: now)
        try review.addComment(text: "this box", time: 4, region: region, now: now)
        return review
    }

    /// `review` with the comment `id` in `state`, as a stored review would
    /// read: the way to a state no rule built here leads to.
    private func stored(_ review: Review, _ id: String, as state: CommentState) throws -> Review {
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(review)) as? [String: Any])
        var comments = try #require(object["comments"] as? [[String: Any]])
        let index = try #require(comments.firstIndex { $0["id"] as? String == id })
        comments[index]["state"] = state.rawValue
        object["comments"] = comments
        return try JSONDecoder().decode(Review.self, from: JSONSerialization.data(withJSONObject: object))
    }

    private func payload(_ batch: Batch, _ review: Review, context: String? = nil) -> BatchPayload {
        BatchPayload.make(
            batch: batch, review: review, context: context,
            keyframe: { "/support/frames/\($0.rawValue).png" }, crop: { "/support/crops/\($0.rawValue).png" }
        )
    }

    // MARK: - Sending

    @Test func sendingTakesEveryQueuedCommentIntoOneBatchInTimeOrder() throws {
        var review = try queued()

        let batch = try review.sendBatch(now: sent)

        #expect(batch == Batch(
            id: BatchID(rawValue: "7f3a9c21-b1"), sentAt: sent,
            comments: [CommentID(rawValue: "7f3a9c21-c2"), CommentID(rawValue: "7f3a9c21-c1")]
        ))
        #expect(review.comments.map(\.state) == [.sent, .sent])
        #expect(review.comments.map(\.batch) == [batch.id, batch.id])
        #expect(review.queue.isEmpty)
        #expect(review.batches == [batch])
        #expect(try review.batch(batch.id) == batch)
        #expect(batch.id.number == 1)
    }

    @Test func anEmptyQueueIsRefusedAndASecondSendTakesOnlyWhatWasQueuedSince() throws {
        var review = try queued()
        #expect(throws: ReviewError.emptyQueue) { var empty = self.review(); try empty.sendBatch(now: sent) }
        try review.sendBatch(now: sent)
        #expect(throws: ReviewError.emptyQueue) { try review.sendBatch(now: sent) }

        let later = try review.addComment(text: "and this", time: 15, now: now)
        let second = try review.sendBatch(now: sent)

        #expect(second.id == BatchID(rawValue: "7f3a9c21-b2"))
        #expect(second.comments == [later.id])
        #expect(review.batches.count == 2)
        #expect(ReviewError.emptyQueue.message == "the queue is empty: there is no comment to send")
    }

    @Test func aSentCommentCanNoLongerBeEditedOrDeletedAndAnUnknownBatchIsRefused() throws {
        var review = try queued()
        try review.sendBatch(now: sent)
        let id = CommentID(rawValue: "7f3a9c21-c1")

        #expect(throws: ReviewError.notQueued(id, .sent)) { try review.editComment(id, text: "new") }
        #expect(throws: ReviewError.notQueued(id, .sent)) { try review.deleteComment(id) }
        #expect(throws: ReviewError.unknownBatch("7f3a9c21-b9")) { try review.batch(BatchID(rawValue: "7f3a9c21-b9")) }
    }

    @Test func theTranscriptLinesGivenAtTheSendAreKeptOnTheBatch() throws {
        var review = try queued()
        let lines = [BatchPayload.Line(start: 0, end: 6.067, text: "The first scene.")]

        let batch = try review.sendBatch(
            transcripts: [CommentID(rawValue: "7f3a9c21-c1"): lines, CommentID(rawValue: "7f3a9c21-c9"): lines], now: sent
        )

        #expect(batch.transcripts == [CommentID(rawValue: "7f3a9c21-c1"): lines])
        #expect(payload(batch, review).comments.map(\.transcript) == [[], lines])
    }

    // MARK: - Finished, and going out again

    @Test func aBatchIsFinishedOnceEveryCommentIsDoneOrFailed() throws {
        var review = try queued()
        let batch = try review.sendBatch(now: sent)
        #expect(!review.isFinished(batch.id))

        let half = try stored(review, "7f3a9c21-c2", as: .done)
        #expect(!half.isFinished(batch.id))
        let whole = try stored(half, "7f3a9c21-c1", as: .failed)
        #expect(whole.isFinished(batch.id))
        #expect(!whole.isFinished(BatchID(rawValue: "7f3a9c21-b9")))
    }

    @Test func requeueingPutsTheUnfinishedCommentsBackToSentAndLeavesTheFinishedOnes() throws {
        var review = try queued()
        let batch = try review.sendBatch(now: sent)
        try review.addComment(text: "still queued", time: 1, now: now)
        var taken = try stored(try stored(review, "7f3a9c21-c2", as: .done), "7f3a9c21-c1", as: .working)
        #expect(taken.comments.map(\.state) == [.queued, .done, .working])

        taken.requeue(batch.id)

        #expect(taken.comments.map(\.state) == [.queued, .done, .sent])
        // Only what isn't finished goes out again.
        #expect(payload(batch, taken).comments.map(\.id) == ["7f3a9c21-c1"])
    }

    // MARK: - The payload

    @Test func thePayloadCarriesTheBatchTheVideoAndEachCommentWithItsImages() throws {
        var review = try queued()
        let batch = try review.sendBatch(now: sent)

        let payload = payload(batch, review)

        #expect(payload.batch == .init(id: "7f3a9c21-b1", sentAt: "2026-10-04T12:00:00Z"))
        #expect(payload.video == .init(path: "/videos/sample.mp4", contentHash: Self.hash, duration: 21.233, title: "sample"))
        #expect(payload.context == nil)
        #expect(payload.comments == [
            .init(
                id: "7f3a9c21-c2", time: 4, text: "this box", keyframePath: "/support/frames/7f3a9c21-c2.png",
                region: region, cropPath: "/support/crops/7f3a9c21-c2.png", transcript: []
            ),
            .init(
                id: "7f3a9c21-c1", time: 10, text: "too fast", keyframePath: "/support/frames/7f3a9c21-c1.png",
                region: nil, cropPath: nil, transcript: []
            ),
        ])
    }

    @Test func thePayloadIsOneJSONObjectWithSortedKeysPlainSlashesAndNullsWrittenOut() throws {
        var review = try queued()
        let batch = try review.sendBatch(now: sent)

        let json = String(decoding: payload(batch, review).encoded(), as: UTF8.self)

        #expect(json == #"{"batch":{"id":"7f3a9c21-b1","sentAt":"2026-10-04T12:00:00Z"},"#
            + #""comments":[{"cropPath":"/support/crops/7f3a9c21-c2.png","id":"7f3a9c21-c2","#
            + #""keyframePath":"/support/frames/7f3a9c21-c2.png","region":{"h":0.2,"w":0.3,"x":0.1,"y":0.2},"#
            + #""text":"this box","time":4,"transcript":[]},"#
            + #"{"cropPath":null,"id":"7f3a9c21-c1","keyframePath":"/support/frames/7f3a9c21-c1.png","region":null,"#
            + #""text":"too fast","time":10,"transcript":[]}],"#
            + #""context":null,"#
            + #""video":{"contentHash":"\#(Self.hash)","duration":21.233,"path":"/videos/sample.mp4","title":"sample"}}"#)
        #expect(try JSONDecoder().decode(BatchPayload.self, from: Data(json.utf8)) == payload(batch, review))
    }

    @Test func aContextGivenGoesOutAsItsText() throws {
        var review = try queued()
        let batch = try review.sendBatch(now: sent)

        let json = String(decoding: payload(batch, review, context: "# Context: sample").encoded(), as: UTF8.self)

        #expect(json.contains(##""context":"# Context: sample""##))
    }
}
