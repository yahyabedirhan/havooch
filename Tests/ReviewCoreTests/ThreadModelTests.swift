import Foundation
import ReviewCore
import Testing

/// The fixture's content hash starts with these digits; any hex will do.
let hash = "f92cbb2a0123456789abcdef"
let now = Date(timeIntervalSince1970: 1_790_000_000)

func newReview() -> VideoReview {
    VideoReview(video: VideoInfo(contentHash: hash, title: "sample.mp4", duration: 21.233, path: "/videos/sample.mp4"))
}

func thread(_ number: Int) -> ThreadID { ItemID("t-f92cbb2a-\(number)")! }
func message(_ number: Int) -> MessageID { ItemID("m-f92cbb2a-\(number)")! }
func send(_ number: Int) -> SendID { ItemID("s-f92cbb2a-\(number)")! }

@Suite("Threads and messages")
struct ThreadModelTests {
    @Test("a new review has the General thread, number 0, with no frame and no state")
    func general() {
        let review = newReview()
        #expect(review.threads.count == 1)
        #expect(review.general.id == thread(0))
        #expect(review.general.number == 0)
        #expect(review.general.time == nil)
        #expect(review.general.isGeneral)
        #expect(review.general.state == nil)
        #expect(review.nextThreadNumber == 1)
    }

    @Test("a message on a frame starts a thread, numbered from 1, keyed by the exact frame time")
    func startsThread() throws {
        var review = newReview()
        let written = try review.write(text: "  The title is cut off\n", at: 10, now: now)
        #expect(written.startedThread)
        #expect(written.thread.id == thread(1))
        #expect(written.thread.time == 10)
        #expect(written.message.id == message(1))
        #expect(written.message.text == "The title is cut off")
        #expect(written.message.author == .person)
        #expect(written.message.kind == .message)
        #expect(written.message.state == .queued)
        #expect(written.message.sendID == nil)
        #expect(review.thread(atFrame: 10) == written.thread)
    }

    @Test("two messages at the same frame are in one thread; one frame later starts another")
    func joins() throws {
        var review = newReview()
        try review.write(text: "Moment", at: 10, now: now)
        let region = try Region(x: 0.47, y: 0.27, w: 0.29, h: 0.15)
        let second = try review.write(text: "This box", at: 10, region: region, now: now)
        let third = try review.write(text: "Another box", at: 10, region: region, now: now)
        let later = try review.write(text: "Next frame", at: 10.034, now: now)
        #expect(!second.startedThread && !third.startedThread)
        #expect(second.thread.id == thread(1))
        #expect(review.thread(thread(1))?.messages.map(\.id) == [message(1), message(2), message(3)])
        #expect(review.thread(thread(1))?.hasRegion == true)
        #expect(later.startedThread)
        #expect(later.thread.id == thread(2))
    }

    @Test("threads are General first, then in time order, whatever the order they started in")
    func timeOrder() throws {
        var review = newReview()
        try review.write(text: "later", at: 12.5, now: now)
        try review.write(text: "earlier", at: 3, now: now)
        try review.write(text: "on General", at: nil, now: now)
        #expect(review.threads.map(\.number) == [0, 2, 1])
        #expect(review.queue.map(\.id) == [message(3), message(2), message(1)])
    }

    @Test("a message on a thread joins it: General with no time, a frame thread at its own frame or with no time")
    func onThread() throws {
        var review = newReview()
        try review.write(text: "first", at: 10, now: now)
        let general = try review.write(text: "In general", at: nil, to: thread(0), now: now)
        let follow = try review.write(text: "Follow-up", at: nil, to: thread(1), now: now)
        let same = try review.write(text: "Same frame", at: 10, to: thread(1), now: now)
        #expect(general.thread.id == thread(0))
        #expect(follow.thread.id == thread(1) && same.thread.id == thread(1))
        #expect(review.threads.count == 2)
    }

    @Test("a message on a thread at another frame, or on General with a frame or a region, is refused")
    func onThreadRefused() throws {
        var review = newReview()
        try review.write(text: "first", at: 10, now: now)
        let before = review
        #expect(throws: ReviewRefusal.frameMismatch(thread(1), time: 12)) {
            try review.write(text: "x", at: 12, to: thread(1), now: now)
        }
        #expect(throws: ReviewRefusal.noFrame) { try review.write(text: "x", at: 12, to: thread(0), now: now) }
        let region = try Region(x: 0, y: 0, w: 0.5, h: 0.5)
        #expect(throws: ReviewRefusal.noFrame) { try review.write(text: "x", at: nil, region: region, to: thread(0), now: now) }
        #expect(throws: ReviewRefusal.noFrame) { try review.write(text: "x", at: nil, region: region, now: now) }
        #expect(throws: ReviewRefusal.unknownID("t-f92cbb2a-7")) { try review.write(text: "x", at: nil, to: thread(7), now: now) }
        #expect(throws: ReviewRefusal.otherVideo("t-0a1b2c3d-1")) {
            try review.write(text: "x", at: nil, to: ItemID("t-0a1b2c3d-1")!, now: now)
        }
        #expect(throws: ReviewRefusal.emptyText) { try review.write(text: " \n", at: 10, now: now) }
        #expect(review == before)
    }

    @Test("a thread reference is a number of the review or a full id of its video")
    func threadRef() throws {
        var review = newReview()
        try review.write(text: "first", at: 10, now: now)
        #expect(try review.threadID(#require(ThreadRef("0"))) == thread(0))
        #expect(try review.threadID(#require(ThreadRef("1"))) == thread(1))
        #expect(try review.threadID(#require(ThreadRef("t-f92cbb2a-1"))) == thread(1))
        #expect(throws: ReviewRefusal.unknownID("t-f92cbb2a-2")) { try review.threadID(#require(ThreadRef("2"))) }
        #expect(throws: ReviewRefusal.otherVideo("t-0a1b2c3d-1")) { try review.threadID(#require(ThreadRef("t-0a1b2c3d-1"))) }
        #expect(ThreadRef("m-f92cbb2a-1") == nil)
        #expect(ThreadRef("one") == nil)
    }

    @Test("a queued message can be edited and deleted; a sent one can't")
    func editDelete() throws {
        var review = newReview()
        try review.write(text: "Too fast", at: 10, now: now)
        try review.write(text: "Typo", at: 10, now: now)
        #expect(try review.edit(message(1), text: " Far too fast ").text == "Far too fast")
        let deleted = try review.delete(message(2))
        #expect(deleted.message.id == message(2))
        #expect(!deleted.removedThread)
        try review.send(at: now)
        let before = review
        #expect(throws: ReviewRefusal.notQueued(message(1), .sent)) { try review.edit(message(1), text: "new") }
        #expect(throws: ReviewRefusal.notQueued(message(1), .sent)) { try review.delete(message(1)) }
        #expect(throws: ReviewRefusal.unknownID("m-f92cbb2a-2")) { try review.delete(message(2)) }
        #expect(throws: ReviewRefusal.emptyText) {
            var copy = newReview()
            try copy.write(text: "x", at: 1, now: now)
            try copy.edit(message(1), text: "  ")
        }
        #expect(review == before)
    }

    @Test("deleting a thread's last message removes the thread, and its number isn't given again; General stays")
    func deleteLast() throws {
        var review = newReview()
        try review.write(text: "Only one", at: 10, now: now)
        let deleted = try review.delete(message(1))
        #expect(deleted.removedThread)
        #expect(deleted.thread == thread(1))
        #expect(review.thread(thread(1)) == nil)
        #expect(try review.write(text: "Again", at: 10, now: now).thread.id == thread(2))
        try review.write(text: "General", at: nil, now: now)
        #expect(try review.delete(message(3)).removedThread == false)
        #expect(review.general.messages.isEmpty)
    }

    @Test("a send takes every queued message on any thread at once, and nothing else")
    func send() throws {
        var review = newReview()
        try review.write(text: "a", at: 10, now: now)
        try review.write(text: "b", at: 12.5, now: now)
        try review.write(text: "c", at: nil, now: now)
        let sent = try review.send(at: now)
        #expect(sent.id == ReviewCore.ItemID("s-f92cbb2a-1"))
        #expect(sent.messageIDs == [message(3), message(1), message(2)])
        #expect(review.queue.isEmpty)
        #expect(review.threads.flatMap(\.messages).allSatisfy { $0.state == .sent && $0.sendID == sent.id })
        #expect(throws: ReviewRefusal.nothingQueued) { try review.send(at: now) }
        try review.write(text: "follow-up", at: nil, to: thread(1), now: now)
        #expect(try review.send(at: now).messageIDs == [message(4)])
        #expect(review.sends.map(\.id.number) == [1, 2])
    }

    @Test("the popover frame is kept per thread and reads back")
    func popoverFrame() throws {
        var review = newReview()
        try review.write(text: "a", at: 10, now: now)
        let frame = PopoverFrame(x: 0.1, y: 0.2, w: 0.3, h: 0.4)
        try review.setPopoverFrame(thread(1), frame)
        #expect(review.thread(thread(1))?.popoverFrame == frame)
        #expect(throws: ReviewRefusal.unknownID("t-f92cbb2a-9")) { try review.setPopoverFrame(thread(9), frame) }
        #expect(try JSONDecoder().decode(VideoReview.self, from: JSONEncoder().encode(review)) == review)
    }

    @Test("a review reads back as it was, counters included")
    func roundTrip() throws {
        var review = newReview()
        try review.write(text: "a", at: 10, now: now)
        try review.delete(message(1))
        let decoded = try JSONDecoder().decode(VideoReview.self, from: JSONEncoder().encode(review))
        #expect(decoded == review)
        var again = decoded
        #expect(try again.write(text: "b", at: 10, now: now).thread.id == thread(2))
        #expect(again.thread(thread(2))?.messages.first?.id == message(2))
    }
}

@Suite("Ids")
struct ItemIDTests {
    @Test("an id carries its kind, the video's hash prefix and its counter", arguments: [
        ("t-f92cbb2a-0", ItemID.Kind.thread, 0), ("m-f92cbb2a-12", .message, 12), ("s-0a1b2c3d-3", .send, 3),
    ])
    func reads(text: String, kind: ItemID.Kind, number: Int) throws {
        let id = try #require(ItemID(text))
        #expect(id.kind == kind)
        #expect(id.number == number)
        #expect(id.text == text)
        #expect(id.hash8 == String(text.dropFirst(2).prefix(8)))
    }

    @Test("what isn't an id is refused", arguments: [
        "t-f92cbb2a", "x-f92cbb2a-1", "t-F92CBB2A-1", "t-f92cbb2-1", "t-f92cbb2a-01", "t-f92cbb2a--1", "c-00000001", "t-f92cbb2a-1a",
    ])
    func refuses(text: String) {
        #expect(ItemID(text) == nil)
    }

    @Test("an id is written as JSON text and reads back")
    func json() throws {
        let id = thread(3)
        let data = try JSONEncoder().encode([id])
        #expect(String(decoding: data, as: UTF8.self) == #"["t-f92cbb2a-3"]"#)
        #expect(try JSONDecoder().decode([ItemID].self, from: data) == [id])
    }
}
