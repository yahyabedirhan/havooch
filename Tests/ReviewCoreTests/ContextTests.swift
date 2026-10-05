import Foundation
import ReviewCore
import Testing

/// When a send carries the video context: once per listener session and
/// video, and again when the text changed.
@Suite("The context, once per listener session")
struct ContextTests {
    static let one = ListenerSession(key: "listener-1", name: "Claude Code", place: "/work")
    static let two = ListenerSession(key: "listener-2", name: "Claude Code", place: "/work")
    static let send = SendRef(sendID: ItemID("s-00000000-1")!, contentHash: "abc")

    private func at(_ seconds: TimeInterval) -> Date { Date(timeIntervalSince1970: seconds) }

    @Test("the first send of a session has the text, and the next has none")
    func oncePerSession() {
        var outbox = Outbox()
        outbox.waitOpened(by: Self.one, at: at(0))
        #expect(outbox.isContextDue(for: "abc", text: "About the sample"))

        #expect(outbox.context(for: "abc", text: "About the sample") == "About the sample")

        #expect(!outbox.isContextDue(for: "abc", text: "About the sample"))
        #expect(outbox.context(for: "abc", text: "About the sample") == nil)
        // A wait from the same session keeps what it has.
        outbox.waitOpened(by: Self.one, at: at(10))
        #expect(outbox.context(for: "abc", text: "About the sample") == nil)
    }

    @Test("a changed text is sent again, once")
    func changed() {
        var outbox = Outbox()
        outbox.waitOpened(by: Self.one, at: at(0))
        _ = outbox.context(for: "abc", text: "About the sample")

        let longer = "About the sample\n\n## Note from the reviewer\n\nMind the intro"
        #expect(outbox.context(for: "abc", text: longer) == longer)
        #expect(outbox.context(for: "abc", text: longer) == nil)
        // One letter is a change, at the same length too.
        #expect(outbox.context(for: "abc", text: "About the simple") == "About the simple")
        // Back to a text the session had before: it's a change again.
        #expect(outbox.context(for: "abc", text: "About the sample") == "About the sample")
    }

    @Test("each video has its own context")
    func perVideo() {
        var outbox = Outbox()
        outbox.waitOpened(by: Self.one, at: at(0))
        #expect(outbox.context(for: "abc", text: "About the sample") == "About the sample")
        // Another video with the same words: this session hasn't had it for that video.
        #expect(outbox.context(for: "def", text: "About the sample") == "About the sample")
        #expect(outbox.context(for: "abc", text: "About the sample") == nil)
        #expect(outbox.context(for: "def", text: "About the sample") == nil)
    }

    @Test("a new listener session gets every video's context again")
    func newSession() {
        var outbox = Outbox()
        outbox.waitOpened(by: Self.one, at: at(0))
        _ = outbox.context(for: "abc", text: "About the sample")
        _ = outbox.context(for: "def", text: "About the other")

        outbox.waitOpened(by: Self.two, at: at(30))

        #expect(outbox.contextSent.isEmpty)
        #expect(outbox.context(for: "abc", text: "About the sample") == "About the sample")
        #expect(outbox.context(for: "def", text: "About the other") == "About the other")
        #expect(outbox.context(for: "abc", text: "About the sample") == nil)
    }

    @Test("no text is no context, and the session keeps what it had")
    func noText() {
        var outbox = Outbox()
        outbox.waitOpened(by: Self.one, at: at(0))
        #expect(outbox.context(for: "abc", text: nil) == nil)
        #expect(outbox.context(for: "abc", text: "") == nil)
        #expect(!outbox.isContextDue(for: "abc", text: nil))
        #expect(outbox.contextSent.isEmpty)

        _ = outbox.context(for: "abc", text: "About the sample")
        // The sidecar goes and comes back unchanged: the session still has its text.
        #expect(outbox.context(for: "abc", text: nil) == nil)
        #expect(outbox.context(for: "abc", text: "About the sample") == nil)
    }

    @Test("a send whose reply couldn't be written takes its video's context back with it")
    func undelivered() {
        var outbox = Outbox()
        outbox.enqueue(Self.send)
        outbox.waitOpened(by: Self.one, at: at(0))
        #expect(outbox.deliver(at: at(0)) == Self.send)
        _ = outbox.context(for: "abc", text: "About the sample")
        _ = outbox.context(for: "def", text: "About the other")

        outbox.undelivered(Self.send)

        // The listener never read that payload: the next one carries the text.
        #expect(outbox.context(for: "abc", text: "About the sample") == "About the sample")
        #expect(outbox.context(for: "def", text: "About the other") == nil)
    }

    @Test("on disk the outbox keeps what the session has, so an app restart doesn't send it again")
    func roundTrip() throws {
        var outbox = Outbox()
        outbox.waitOpened(by: Self.one, at: at(0))
        _ = outbox.context(for: "abc", text: "About the sample")

        var read = try JSONDecoder().decode(Outbox.self, from: try JSONEncoder().encode(outbox))

        #expect(read.contextSent == outbox.contextSent)
        read.waitOpened(by: Self.one, at: at(60))
        #expect(read.context(for: "abc", text: "About the sample") == nil)
        #expect(read.context(for: "abc", text: "About the sample, again") == "About the sample, again")
    }
}
