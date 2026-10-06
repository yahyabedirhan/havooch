import Foundation
import ReviewCore
import Testing

@Suite("Unread agent messages")
struct UnreadTests {
    /// A review with thread 1 sent, so the agent can write on it.
    private func sentReview() throws -> VideoReview {
        var review = newReview()
        try review.write(text: "Too fast", at: 10, now: now)
        try review.send(at: now)
        return review
    }

    @Test("a thread with no agent message is read; the person's own messages never make it unread")
    func personOnly() throws {
        let review = try sentReview()
        #expect(review.thread(thread(1))?.isUnread == false)
        #expect(review.general.isUnread == false)
    }

    @Test("an agent reply on a thread the person never opened makes it unread")
    func replyNeverOpened() throws {
        var review = try sentReview()
        try review.reply(on: thread(1), text: "Slowed it down", now: now.addingTimeInterval(5))
        #expect(review.thread(thread(1))?.isUnread == true)
    }

    @Test("opening the thread view clears it, and a later reply makes it unread again")
    func openClears() throws {
        var review = try sentReview()
        try review.reply(on: thread(1), text: "Slowed it down", now: now.addingTimeInterval(5))
        try review.markSeen(thread(1), at: now.addingTimeInterval(10))
        #expect(review.thread(thread(1))?.isUnread == false)
        #expect(review.thread(thread(1))?.lastSeen == now.addingTimeInterval(10))
        try review.ask(on: thread(1), question: "Slower still?", now: now.addingTimeInterval(20))
        #expect(review.thread(thread(1))?.isUnread == true)
    }

    @Test("a reply older than the last opening is read")
    func olderReply() throws {
        var review = try sentReview()
        try review.markSeen(thread(1), at: now.addingTimeInterval(30))
        try review.reply(on: thread(1), text: "Late clock", now: now.addingTimeInterval(20))
        #expect(review.thread(thread(1))?.isUnread == false)
    }

    @Test("an acknowledgement's words make General unread")
    func acknowledgementWords() throws {
        var review = try sentReview()
        try review.acknowledge(send(1), text: "On it", now: now.addingTimeInterval(1))
        #expect(review.general.isUnread)
        #expect(review.thread(thread(1))?.isUnread == false)
    }

    @Test("marking a thread the review doesn't have is refused")
    func unknown() {
        var review = newReview()
        #expect(throws: ReviewRefusal.unknownID(thread(9).text)) { try review.markSeen(thread(9), at: now) }
    }

    @Test("the last opening reads back from JSON")
    func roundTrip() throws {
        var review = try sentReview()
        try review.reply(on: thread(1), text: "Done", now: now.addingTimeInterval(5))
        try review.markSeen(thread(1), at: now.addingTimeInterval(6))
        try review.reply(on: thread(0), text: "Hello", now: now.addingTimeInterval(7))
        let encoder = JSONEncoder()
        let decoded = try JSONDecoder().decode(VideoReview.self, from: encoder.encode(review))
        #expect(decoded == review)
        #expect(decoded.thread(thread(1))?.isUnread == false)
        #expect(decoded.general.isUnread)
    }

    @Test("a thread kept before last openings were counts its agent messages as read")
    func keptBefore() throws {
        var review = try sentReview()
        try review.reply(on: thread(1), text: "Done", now: now.addingTimeInterval(5))
        let encoder = JSONEncoder()
        var object = try #require(JSONSerialization.jsonObject(with: encoder.encode(review)) as? [String: Any])
        var threads = try #require(object["threads"] as? [[String: Any]])
        for index in threads.indices { threads[index]["lastSeen"] = nil }
        object["threads"] = threads
        let old = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(VideoReview.self, from: old)
        #expect(decoded.thread(thread(1))?.isUnread == false)
        #expect(decoded.general.isUnread == false)
    }
}
