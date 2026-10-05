import Foundation
import Testing
import VRReview

@Suite struct ReviewTests {
    static let hash = "7f3a9c21" + String(repeating: "0", count: 56)
    let now = Date(timeIntervalSince1970: 1_000)

    private func review() -> Review {
        Review(video: VideoInfo(contentHash: Self.hash, path: "/videos/sample.mp4", title: "sample", duration: 21.233))
    }

    /// `review` with its queued comments in `state`, as a stored review
    /// would read: the way to a state no rule built here leads to.
    private func stored(_ review: Review, as state: CommentState) throws -> Review {
        let json = String(decoding: try JSONEncoder().encode(review), as: UTF8.self)
        let moved = json.replacingOccurrences(of: #""state":"queued""#, with: #""state":"\#(state.rawValue)""#)
        return try JSONDecoder().decode(Review.self, from: Data(moved.utf8))
    }

    @Test func aNewCommentIsQueuedWithItsIdItsTimeAndItsText() throws {
        var review = review()
        let comment = try review.addComment(text: "the title is small", time: 10, now: now)
        #expect(comment == Comment(id: CommentID(rawValue: "7f3a9c21-c1"), time: 10, text: "the title is small", state: .queued, createdAt: now))
        #expect(review.comments == [comment])
        #expect(review.queue == [comment])
        #expect(try review.comment(comment.id) == comment)
    }

    @Test func aCommentOnARegionKeepsItAndAStoredReviewBringsItBack() throws {
        var review = review()
        let region = try #require(Region(x: 0.48, y: 0.3, w: 0.28, h: 0.12))
        let pointed = try review.addComment(text: "this key", time: 10, region: region, now: now)
        let plain = try review.addComment(text: "the whole frame", time: 12, now: now)
        #expect(pointed == Comment(id: CommentID(rawValue: "7f3a9c21-c1"), time: 10, text: "this key", region: region, state: .queued, createdAt: now))
        #expect(plain.region == nil)
        #expect(try review.editComment(pointed.id, text: "that key").region == region)
        let back = try JSONDecoder().decode(Review.self, from: JSONEncoder().encode(review))
        #expect(back == review)
        #expect(back.comments.map(\.region) == [region, nil])
    }

    @Test func theQueueIsInTimeOrderWhateverOrderCommentsWereMadeIn() throws {
        var review = review()
        for time in [18.0, 3, 10, 0, 21.233] {
            try review.addComment(text: "at \(time)", time: time, now: now)
        }
        #expect(review.queue.map(\.time) == [0, 3, 10, 18, 21.233])
        #expect(review.queue.map(\.id.rawValue) == ["7f3a9c21-c4", "7f3a9c21-c2", "7f3a9c21-c3", "7f3a9c21-c1", "7f3a9c21-c5"])
    }

    @Test func commentsAtTheSameTimeKeepTheOrderTheyWereMadeIn() throws {
        var review = review()
        for text in ["first", "second", "third"] {
            try review.addComment(text: text, time: 5, now: now)
        }
        try review.addComment(text: "earlier", time: 4, now: now)
        #expect(review.queue.map(\.text) == ["earlier", "first", "second", "third"])
    }

    @Test func anIdIsNeverGivenTwice() throws {
        var review = review()
        let first = try review.addComment(text: "one", time: 1, now: now)
        try review.deleteComment(first.id)
        let second = try review.addComment(text: "two", time: 1, now: now)
        #expect(first.id.rawValue == "7f3a9c21-c1")
        #expect(second.id.rawValue == "7f3a9c21-c2")
    }

    @Test func theTextIsKeptWithoutTheBlankSpaceAroundIt() throws {
        var review = review()
        let comment = try review.addComment(text: "  two\nlines \n", time: 1, now: now)
        #expect(comment.text == "two\nlines")
        #expect(try review.editComment(comment.id, text: "\tnew text ").text == "new text")
    }

    @Test(arguments: ["", "   ", "\n\t"])
    func aCommentWithoutTextIsRefused(text: String) throws {
        var review = review()
        #expect(throws: ReviewError.emptyText) { try review.addComment(text: text, time: 1, now: now) }
        let comment = try review.addComment(text: "kept", time: 1, now: now)
        #expect(throws: ReviewError.emptyText) { try review.editComment(comment.id, text: text) }
        #expect(review.queue.map(\.text) == ["kept"])
    }

    @Test(arguments: [-0.001, 21.234, 100, Double.nan, Double.infinity])
    func aTimeOutsideTheVideoIsRefusedAndTakesNoId(time: Double) throws {
        var review = review()
        #expect(throws: ReviewError.self) { try review.addComment(text: "late", time: time, now: now) }
        #expect(throws: ReviewError.self) { try review.checkedText("late", at: time) }
        #expect(review.comments.isEmpty)
        #expect(try review.addComment(text: "in time", time: 21.233, now: now).id.rawValue == "7f3a9c21-c1")
    }

    @Test func editChangesTheTextAndNothingElse() throws {
        var review = review()
        let early = try review.addComment(text: "early", time: 3, now: now)
        let late = try review.addComment(text: "late", time: 18, now: now)
        let edited = try review.editComment(late.id, text: "later")
        #expect(edited == Comment(id: late.id, time: 18, text: "later", state: .queued, createdAt: now))
        #expect(review.queue == [early, edited])
    }

    @Test func deleteTakesTheCommentOutOfTheQueue() throws {
        var review = review()
        let early = try review.addComment(text: "early", time: 3, now: now)
        let late = try review.addComment(text: "late", time: 18, now: now)
        try review.deleteComment(early.id)
        #expect(review.queue == [late])
        #expect(throws: ReviewError.unknownComment("7f3a9c21-c1")) { try review.comment(early.id) }
    }

    @Test func anUnknownIdIsRefusedInWords() throws {
        var review = review()
        try review.addComment(text: "one", time: 1, now: now)
        let other = CommentID(rawValue: "0badf00d-c1")
        #expect(throws: ReviewError.unknownComment("0badf00d-c1")) { try review.editComment(other, text: "x") }
        #expect(throws: ReviewError.unknownComment("0badf00d-c1")) { try review.deleteComment(other) }
        #expect(ReviewError.unknownComment("0badf00d-c1").message == "there is no comment `0badf00d-c1`")
    }

    @Test(arguments: [CommentState.sent, .acknowledged, .working, .done, .failed])
    func onlyAQueuedCommentCanBeEditedOrDeleted(state: CommentState) throws {
        var fresh = review()
        let comment = try fresh.addComment(text: "one", time: 1, now: now)
        var review = try stored(fresh, as: state)
        #expect(try review.comment(comment.id).state == state)
        #expect(throws: ReviewError.notQueued(comment.id, state)) { try review.editComment(comment.id, text: "new") }
        #expect(throws: ReviewError.notQueued(comment.id, state)) { try review.deleteComment(comment.id) }
        #expect(review.comments.map(\.text) == ["one"])
        #expect(review.queue.isEmpty)
        #expect(ReviewError.notQueued(comment.id, state).message
            == "7f3a9c21-c1 is \(state.rawValue); only a queued comment can be edited or deleted")
    }

    @Test func aStoredReviewComesBackWithItsCounter() throws {
        var review = review()
        try review.addComment(text: "one", time: 1, now: now)
        try review.addComment(text: "two", time: 2, now: now)
        var back = try JSONDecoder().decode(Review.self, from: JSONEncoder().encode(review))
        #expect(back == review)
        #expect(try back.addComment(text: "three", time: 3, now: now).id.rawValue == "7f3a9c21-c3")
    }

    @Test func anIdIsStoredAsItsText() throws {
        let id = CommentID(contentHash: Self.hash, number: 3)
        #expect(String(decoding: try JSONEncoder().encode([id]), as: UTF8.self) == #"["7f3a9c21-c3"]"#)
    }
}

@Suite struct CommentStateTests {
    static let allowed: [CommentState: Set<CommentState>] = [
        .draft: [.queued],
        .queued: [.sent],
        .sent: [.acknowledged, .working, .done, .failed],
        .acknowledged: [.working, .done, .failed],
        .working: [.done, .failed],
        .done: [],
        .failed: [],
    ]

    @Test(arguments: CommentState.allCases, CommentState.allCases)
    func aCommentOnlyMovesForward(from: CommentState, to: CommentState) throws {
        let moves = try #require(Self.allowed[from])
        #expect(from.canMove(to: to) == moves.contains(to))
    }
}
