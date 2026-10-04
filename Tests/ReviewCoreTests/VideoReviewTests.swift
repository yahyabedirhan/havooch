import Foundation
import ReviewCore
import Testing

@Suite("A video's review")
struct VideoReviewTests {
    static let video = VideoInfo(contentHash: "abc", title: "sample", duration: 21.233, path: "/videos/sample.mp4")
    static let first = ItemID("c-00000001")!
    static let second = ItemID("c-00000002")!
    static let third = ItemID("c-00000003")!

    /// A review as it could be read from disk, with one comment in `state`.
    private func review(with state: CommentState) throws -> VideoReview {
        let json = """
            {"video": {"contentHash": "abc", "title": "sample", "duration": 21.233, "path": "/videos/sample.mp4"},
             "comments": [{"id": "c-00000001", "time": 10, "text": "Too fast", "state": "\(state.rawValue)"}]}
            """
        return try JSONDecoder().decode(VideoReview.self, from: Data(json.utf8))
    }

    @Test("a comment is queued with its id, its time and its text")
    func add() throws {
        var review = VideoReview(video: Self.video)
        let comment = try review.addComment(id: Self.first, time: 10, text: "  Too fast\n")
        #expect(comment.id == Self.first)
        #expect(comment.time == 10)
        #expect(comment.text == "Too fast")
        #expect(comment.state == .queued)
        #expect(review.comments == [comment])
        #expect(review.comment(Self.first) == comment)
    }

    @Test("comments and the queue are in time order, whatever the order they were added in")
    func timeOrder() throws {
        var review = VideoReview(video: Self.video)
        try review.addComment(id: Self.first, time: 12.5, text: "later")
        try review.addComment(id: Self.second, time: 3, text: "earlier")
        try review.addComment(id: Self.third, time: 12.5, text: "same time, added after")
        #expect(review.comments.map(\.id) == [Self.second, Self.first, Self.third])
        #expect(review.queue.map(\.id) == [Self.second, Self.first, Self.third])
    }

    @Test("a comment with no words is refused, and nothing changes")
    func emptyText() throws {
        var review = VideoReview(video: Self.video)
        #expect(throws: ReviewRefusal.emptyText) { try review.addComment(id: Self.first, time: 1, text: " \n ") }
        #expect(review.comments.isEmpty)

        try review.addComment(id: Self.first, time: 1, text: "kept")
        #expect(throws: ReviewRefusal.emptyText) { try review.editComment(Self.first, text: "") }
        #expect(review.comment(Self.first)?.text == "kept")
    }

    @Test("editing changes a queued comment's text and nothing else")
    func edit() throws {
        var review = VideoReview(video: Self.video)
        try review.addComment(id: Self.first, time: 10, text: "Too fast")
        let edited = try review.editComment(Self.first, text: " Slower here ")
        #expect(edited.text == "Slower here")
        #expect(review.comments == [edited])
        #expect(edited.time == 10)
        #expect(edited.state == .queued)
    }

    @Test("deleting removes a queued comment from the comments and the queue")
    func delete() throws {
        var review = VideoReview(video: Self.video)
        try review.addComment(id: Self.first, time: 10, text: "Too fast")
        try review.addComment(id: Self.second, time: 12, text: "Good")
        let deleted = try review.deleteComment(Self.first)
        #expect(deleted.id == Self.first)
        #expect(review.comments.map(\.id) == [Self.second])
        #expect(review.queue.map(\.id) == [Self.second])
    }

    @Test("an unknown id is refused")
    func unknown() throws {
        var review = VideoReview(video: Self.video)
        try review.addComment(id: Self.first, time: 10, text: "Too fast")
        #expect(throws: ReviewRefusal.unknownComment("c-00000002")) { try review.editComment(Self.second, text: "x") }
        #expect(throws: ReviewRefusal.unknownComment("c-00000002")) { try review.deleteComment(Self.second) }
        #expect(review.comments.count == 1)
    }

    @Test("only a queued comment can be edited or deleted", arguments: [
        CommentState.sent, .acknowledged, .working, .done, .failed,
    ])
    func record(state: CommentState) throws {
        var review = try review(with: state)
        let before = review
        #expect(throws: ReviewRefusal.notQueued(Self.first, state)) { try review.editComment(Self.first, text: "new") }
        #expect(throws: ReviewRefusal.notQueued(Self.first, state)) { try review.deleteComment(Self.first) }
        #expect(review == before)
        #expect(review.queue.isEmpty)
    }

    @Test("a refusal says why in one line")
    func lines() {
        #expect(ReviewRefusal.emptyText.line == "a comment needs text")
        #expect(ReviewRefusal.notQueued(Self.first, .sent).line == "c-00000001 is sent, and only a queued comment can change")
        #expect(ReviewRefusal.unknownComment("c-9").line.hasPrefix("no comment `c-9` on this video"))
    }

    @Test("a review reads back from JSON as it was written")
    func roundTrip() throws {
        var review = VideoReview(video: Self.video)
        try review.addComment(id: Self.first, time: 10, text: "Too fast")
        let data = try JSONEncoder().encode(review)
        #expect(try JSONDecoder().decode(VideoReview.self, from: data) == review)
    }
}

@Suite("Comment states")
struct CommentStateTests {
    @Test("a comment moves forward only, and may skip a state")
    func forward() {
        #expect(CommentState.queued.canMove(to: .sent))
        #expect(CommentState.sent.canMove(to: .acknowledged))
        #expect(CommentState.sent.canMove(to: .working))
        #expect(CommentState.acknowledged.canMove(to: .done))
        #expect(CommentState.working.canMove(to: .failed))
        #expect(!CommentState.sent.canMove(to: .queued))
        #expect(!CommentState.working.canMove(to: .acknowledged))
        #expect(!CommentState.sent.canMove(to: .sent))
    }

    @Test("done and failed are final", arguments: CommentState.allCases)
    func final(next: CommentState) {
        #expect(!CommentState.done.canMove(to: next))
        #expect(!CommentState.failed.canMove(to: next))
    }

    @Test("only a queued comment can change")
    func editable() {
        #expect(CommentState.allCases.filter(\.isEditable) == [.queued])
    }
}

@Suite("Item ids")
struct ItemIDTests {
    @Test("a new id has its kind's prefix and 8 hex digits")
    func make() throws {
        for kind in ItemID.Kind.allCases {
            let id = ItemID.make(kind)
            #expect(id.kind == kind)
            #expect(id.text.wholeMatch(of: /[cbm]-[0-9a-f]{8}/) != nil)
            #expect(id.text.hasPrefix(kind.rawValue + "-"))
            #expect(ItemID(id.text) == id)
        }
        #expect(ItemID.make(.comment) != ItemID.make(.comment))
    }

    @Test("text that isn't an id doesn't read", arguments: ["", "c-", "c-123", "x-0000000a", "c-0000000G", "c-0000000A", "c0000000a", "c-0000000a-b"])
    func invalid(text: String) {
        #expect(ItemID(text) == nil)
    }

    @Test("an id is one string in JSON")
    func json() throws {
        let id = try #require(ItemID("b-0000000a"))
        #expect(String(decoding: try JSONEncoder().encode([id]), as: UTF8.self) == "[\"b-0000000a\"]")
        #expect(try JSONDecoder().decode([ItemID].self, from: Data("[\"b-0000000a\"]".utf8)) == [id])
        #expect(throws: DecodingError.self) { try JSONDecoder().decode([ItemID].self, from: Data("[\"nope\"]".utf8)) }
    }
}
