import Foundation
import ReviewCore
import Testing

/// A review as it could be read from disk: a batch `b-00000001` of three
/// comments in `states`, in time order from 5 s.
private func sentReview(_ states: [CommentState]) throws -> VideoReview {
    let comments = states.enumerated().map { index, state in
        """
        {"id": "c-0000000\(index + 1)", "time": \(5 * (index + 1)), "text": "Comment \(index + 1)", "state": "\(state.rawValue)",
         "batchID": "b-00000001"}
        """
    }
    let ids = states.indices.map { "\"c-0000000\($0 + 1)\"" }.joined(separator: ", ")
    let json = """
        {"video": {"contentHash": "abc", "title": "sample", "duration": 21.2333, "path": "/videos/sample.mp4"},
         "comments": [\(comments.joined(separator: ", "))],
         "batches": [{"id": "b-00000001", "sentAt": 0, "commentIDs": [\(ids)]}]}
        """
    return try JSONDecoder().decode(VideoReview.self, from: Data(json.utf8))
}

@Suite("Sending a batch")
struct BatchTests {
    static let video = VideoInfo(contentHash: "abc", title: "sample", duration: 21.2333, path: "/videos/sample.mp4")
    static let batch = ItemID("b-00000001")!
    static let sentAt = Date(timeIntervalSince1970: 1_790_000_000)

    private func id(_ number: Int) -> ItemID { ItemID("c-0000000\(number)")! }

    @Test("a send moves every queued comment to sent as one batch, in time order")
    func send() throws {
        var review = VideoReview(video: Self.video)
        try review.addComment(id: id(1), time: 12.5, text: "Later")
        try review.addComment(id: id(2), time: 3, text: "Earlier")

        let batch = try review.send(batchID: Self.batch, at: Self.sentAt)

        #expect(batch == review.batch(Self.batch))
        #expect(batch.id == Self.batch)
        #expect(batch.sentAt == Self.sentAt)
        #expect(batch.commentIDs == [id(2), id(1)])
        #expect(review.comments.map(\.state) == [.sent, .sent])
        #expect(review.comments.map(\.batchID) == [Self.batch, Self.batch])
        #expect(review.queue.isEmpty)
        #expect(review.batches == [batch])
        #expect(review.comments(of: Self.batch).map(\.id) == [id(2), id(1)])
    }

    @Test("a send with nothing queued is refused, and no batch is made")
    func nothingQueued() throws {
        var review = VideoReview(video: Self.video)
        #expect(throws: ReviewRefusal.nothingQueued) { try review.send(batchID: Self.batch, at: Self.sentAt) }
        try review.addComment(id: id(1), time: 3, text: "Once")
        try review.send(batchID: Self.batch, at: Self.sentAt)
        let before = review
        #expect(throws: ReviewRefusal.nothingQueued) { try review.send(batchID: ItemID("b-00000002")!, at: Self.sentAt) }
        #expect(review == before)
        #expect(ReviewRefusal.nothingQueued.line.hasPrefix("no comment is queued"))
    }

    @Test("a second send carries only what was queued since the first")
    func secondBatch() throws {
        var review = VideoReview(video: Self.video)
        try review.addComment(id: id(1), time: 3, text: "First")
        try review.send(batchID: Self.batch, at: Self.sentAt)
        try review.addComment(id: id(2), time: 1, text: "Second")
        let second = try review.send(batchID: ItemID("b-00000002")!, at: Self.sentAt.addingTimeInterval(60))

        #expect(second.commentIDs == [id(2)])
        #expect(review.batches.map(\.id.text) == ["b-00000001", "b-00000002"])
        #expect(review.comment(id(1))?.batchID == Self.batch)
    }

    @Test("a sent comment is a record: it can't be edited or deleted")
    func record() throws {
        var review = VideoReview(video: Self.video)
        try review.addComment(id: id(1), time: 3, text: "First")
        try review.send(batchID: Self.batch, at: Self.sentAt)
        #expect(throws: ReviewRefusal.notQueued(id(1), .sent)) { try review.editComment(id(1), text: "new") }
        #expect(throws: ReviewRefusal.notQueued(id(1), .sent)) { try review.deleteComment(id(1)) }
    }

    @Test("a batch is finished when every comment in it is done or failed")
    func finished() throws {
        #expect(try !sentReview([.sent, .sent, .sent]).isFinished(Self.batch))
        #expect(try !sentReview([.done, .working, .failed]).isFinished(Self.batch))
        #expect(try sentReview([.done, .failed, .done]).isFinished(Self.batch))
    }

    @Test("a batch that goes back to the queue returns its unfinished comments to sent, and leaves the finished ones")
    func requeue() throws {
        var review = try sentReview([.acknowledged, .done, .working])
        let again = review.requeue(Self.batch)
        #expect(again == [id(1), id(3)])
        #expect(review.comments.map(\.state) == [.sent, .done, .sent])

        var failed = try sentReview([.failed, .sent, .done])
        #expect(failed.requeue(Self.batch) == [id(2)])
        #expect(failed.comments.map(\.state) == [.failed, .sent, .done])
    }
}

@Suite("The batch payload")
struct BatchPayloadTests {
    private func object(_ payload: BatchPayload) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: Data(payload.json.utf8)) as? [String: Any])
    }

    private func payload(_ review: VideoReview, context: String? = nil, lines: [BatchPayload.Line] = []) throws -> BatchPayload {
        BatchPayload.assemble(
            review: review, batch: try #require(review.batch(BatchTests.batch)), context: context,
            transcript: { _ in lines },
            images: { comment in
                .init(keyframe: "/data/frames/\(comment.id).png", crop: comment.region.map { _ in "/data/crops/\(comment.id).png" })
            }
        )
    }

    @Test("the payload has the spec's keys: batch, video, context and each comment's id, time, text, images, region and transcript")
    func shape() throws {
        var review = VideoReview(video: BatchTests.video)
        try review.addComment(id: ItemID("c-00000001")!, time: 10, text: "Too fast")
        try review.addComment(
            id: ItemID("c-00000002")!, time: 12.5, text: "This box", region: try Region(x: 0.25, y: 0.2, w: 0.3, h: 0.25)
        )
        try review.send(batchID: BatchTests.batch, at: BatchTests.sentAt)

        let payload = try object(try payload(review))

        #expect(Set(payload.keys) == ["batch", "video", "context", "comments"])
        #expect(payload["batch"] as? [String: String] == ["id": "b-00000001", "sentAt": "2026-09-21T14:13:20Z"])
        // Field by field with typed casts: a number read back compares
        // unequal to a literal through AnyHashable on Linux's Foundation.
        let video = try #require(payload["video"] as? [String: Any])
        #expect(Set(video.keys) == ["path", "contentHash", "duration", "title"])
        #expect(video["path"] as? String == "/videos/sample.mp4")
        #expect(video["contentHash"] as? String == "abc")
        #expect(video["duration"] as? Double == 21.233)
        #expect(video["title"] as? String == "sample")
        #expect(payload["context"] is NSNull)
        let comments = try #require(payload["comments"] as? [[String: Any]])
        #expect(comments.count == 2)
        #expect(Set(comments[0].keys) == ["id", "time", "text", "keyframePath", "region", "cropPath", "transcript"])
        #expect(comments[0]["id"] as? String == "c-00000001")
        #expect(comments[0]["time"] as? Double == 10)
        #expect(comments[0]["text"] as? String == "Too fast")
        #expect(comments[0]["keyframePath"] as? String == "/data/frames/c-00000001.png")
        #expect(comments[0]["region"] is NSNull)
        #expect(comments[0]["cropPath"] is NSNull)
        #expect((comments[0]["transcript"] as? [Any])?.isEmpty == true)
        #expect(Set(comments[1].keys) == ["id", "time", "text", "keyframePath", "region", "cropPath", "transcript"])
        #expect(comments[1]["region"] as? [String: Double] == ["x": 0.25, "y": 0.2, "w": 0.3, "h": 0.25])
        #expect(comments[1]["cropPath"] as? String == "/data/crops/c-00000002.png")
        #expect(comments[1]["time"] as? Double == 12.5)
    }

    @Test("the context and the transcript lines it's given are in the payload")
    func contextAndTranscript() throws {
        var review = VideoReview(video: BatchTests.video)
        try review.addComment(id: ItemID("c-00000001")!, time: 10, text: "Too fast")
        try review.send(batchID: BatchTests.batch, at: BatchTests.sentAt)

        let payload = try object(try payload(
            review, context: "About the queue.", lines: [.init(start: 6.067, end: 14.333, text: "Your comments queue up.")]
        ))

        #expect(payload["context"] as? String == "About the queue.")
        let comment = try #require((payload["comments"] as? [[String: Any]])?.first)
        let lines = try #require(comment["transcript"] as? [[String: Any]])
        #expect(lines.count == 1)
        #expect(lines.first?["start"] as? Double == 6.067)
        #expect(lines.first?["end"] as? Double == 14.333)
        #expect(lines.first?["text"] as? String == "Your comments queue up.")
    }

    @Test("a batch delivered again carries only its unfinished comments, under the same id")
    func unfinishedOnly() throws {
        var review = try sentReview([.acknowledged, .done, .working])
        review.requeue(BatchTests.batch)
        let payload = try payload(review)
        #expect(payload.batch.id == BatchTests.batch)
        #expect(payload.comments.map(\.id.text) == ["c-00000001", "c-00000003"])
    }

    @Test("the payload reads back from its JSON")
    func roundTrip() throws {
        var review = VideoReview(video: BatchTests.video)
        try review.addComment(id: ItemID("c-00000001")!, time: 10, text: "Too fast", region: try Region(x: 0, y: 0, w: 1, h: 1))
        try review.send(batchID: BatchTests.batch, at: BatchTests.sentAt)
        let payload = try payload(review, context: "Text")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        #expect(try decoder.decode(BatchPayload.self, from: Data(payload.json.utf8)) == payload)
    }
}
