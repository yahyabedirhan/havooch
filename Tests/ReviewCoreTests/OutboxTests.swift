import Foundation
import ReviewCore
import Testing

/// The listener's outbox, driven by the time the test gives it.
@Suite("The listener's outbox")
struct OutboxTests {
    static let first = BatchRef(batchID: ItemID("b-00000001")!, contentHash: "abc")
    static let second = BatchRef(batchID: ItemID("b-00000002")!, contentHash: "abc")
    static let third = BatchRef(batchID: ItemID("b-00000003")!, contentHash: "def")
    static let one = ListenerSession(key: "listener-1", name: "Claude Code", place: "/work")
    static let two = ListenerSession(key: "listener-2", name: "Claude Code", place: "/work")

    private func at(_ seconds: TimeInterval) -> Date { Date(timeIntervalSince1970: seconds) }

    @Test("a batch sent while a wait is open is delivered to it, and is taken from then on")
    func deliversToTheOpenWait() {
        var outbox = Outbox()
        outbox.waitOpened(by: Self.one, at: at(0))
        #expect(outbox.deliverNext(at: at(0)) == nil)

        outbox.enqueue(Self.first)
        #expect(outbox.deliverNext(at: at(5)) == Self.first)

        #expect(outbox.pending.isEmpty)
        #expect(outbox.taken == [Self.first])
        // The wait was answered: the next batch needs the next wait.
        #expect(!outbox.isWaitOpen)
        outbox.enqueue(Self.second)
        #expect(outbox.deliverNext(at: at(6)) == nil)
        #expect(outbox.pending == [Self.second])
    }

    @Test("a batch sent with no listener waits, and the next wait gets it; batches go out first in, first out, one per wait")
    func waitsForTheNextWait() {
        var outbox = Outbox()
        outbox.enqueue(Self.first)
        outbox.enqueue(Self.second)
        #expect(outbox.deliverNext(at: at(0)) == nil)
        #expect(outbox.presence(at: at(0)) == .absent)

        outbox.waitOpened(by: Self.one, at: at(10))
        #expect(outbox.deliverNext(at: at(10)) == Self.first)
        #expect(outbox.deliverNext(at: at(10)) == nil)
        outbox.waitOpened(by: Self.one, at: at(20))
        #expect(outbox.deliverNext(at: at(20)) == Self.second)
        #expect(outbox.taken == [Self.first, Self.second])
    }

    @Test("a batch is in line once")
    func enqueuedOnce() {
        var outbox = Outbox()
        outbox.enqueue(Self.first)
        outbox.enqueue(Self.first)
        #expect(outbox.pending == [Self.first])
        outbox.waitOpened(by: Self.one, at: at(0))
        _ = outbox.deliverNext(at: at(0))
        outbox.enqueue(Self.first)
        #expect(outbox.pending.isEmpty)
    }

    @Test("a wait from another holder is a new listener session: the taken batches are first in line again, in the order taken")
    func listenerRestart() {
        var outbox = Outbox()
        outbox.enqueue(Self.first)
        outbox.enqueue(Self.second)
        outbox.waitOpened(by: Self.one, at: at(0))
        _ = outbox.deliverNext(at: at(0))
        outbox.waitOpened(by: Self.one, at: at(1))
        _ = outbox.deliverNext(at: at(1))
        outbox.enqueue(Self.third)

        let requeued = outbox.waitOpened(by: Self.two, at: at(30))

        #expect(requeued == [Self.first, Self.second])
        #expect(outbox.taken.isEmpty)
        #expect(outbox.pending == [Self.first, Self.second, Self.third])
        #expect(outbox.session == Self.two)
        #expect(outbox.deliverNext(at: at(30)) == Self.first)
    }

    @Test("a wait from the same holder keeps what it took: the listener waits again before it works on a batch")
    func sameSession() {
        var outbox = Outbox()
        outbox.enqueue(Self.first)
        outbox.waitOpened(by: Self.one, at: at(0))
        _ = outbox.deliverNext(at: at(0))

        // Its name or place may change; its key tells it's the same session.
        let again = ListenerSession(key: Self.one.key, name: "Claude Code", place: "Herdr pane w1-2")
        #expect(outbox.waitOpened(by: again, at: at(10)).isEmpty)
        #expect(outbox.taken == [Self.first])
        #expect(outbox.session == again)
        // The first session of all has nothing to requeue either.
        var fresh = Outbox()
        #expect(fresh.waitOpened(by: Self.one, at: at(0)).isEmpty)
    }

    @Test("a batch whose reply couldn't be written is first in line again; a finished one is gone")
    func undeliveredAndFinished() {
        var outbox = Outbox()
        outbox.enqueue(Self.first)
        outbox.enqueue(Self.second)
        outbox.waitOpened(by: Self.one, at: at(0))
        _ = outbox.deliverNext(at: at(0))

        outbox.undelivered(Self.first)
        #expect(outbox.taken.isEmpty)
        #expect(outbox.pending == [Self.first, Self.second])
        // Only a taken batch goes back.
        outbox.undelivered(Self.third)
        #expect(outbox.pending == [Self.first, Self.second])

        outbox.waitOpened(by: Self.one, at: at(1))
        _ = outbox.deliverNext(at: at(1))
        outbox.finished(Self.first)
        #expect(outbox.taken.isEmpty)
        // A finished batch isn't requeued for the next session.
        #expect(outbox.waitOpened(by: Self.two, at: at(2)).isEmpty)

        outbox.discard(Self.second)
        #expect(outbox.pending.isEmpty)
    }

    @Test("presence is listening while a wait is open, and absent 5 s after it closed")
    func presenceFollowsTheWait() {
        var outbox = Outbox()
        #expect(outbox.presence(at: at(0)) == .absent)

        outbox.waitOpened(by: Self.one, at: at(0))
        #expect(outbox.presence(at: at(0)) == .listening)
        // An open wait is alive however long it's open.
        #expect(outbox.presence(at: at(3600)) == .listening)

        outbox.waitClosed(at: at(3600))
        #expect(!outbox.isWaitOpen)
        // A listener that runs wait in a loop doesn't flicker between two.
        #expect(outbox.presence(at: at(3604.9)) == .listening)
        #expect(outbox.presence(at: at(3605)) == .absent)
        outbox.waitOpened(by: Self.one, at: at(3610))
        #expect(outbox.presence(at: at(3610)) == .listening)
    }

    @Test("presence is working while a batch is taken and the listener was heard in the last 120 s or waits again")
    func presenceWhileWorking() {
        var outbox = Outbox()
        outbox.enqueue(Self.first)
        outbox.waitOpened(by: Self.one, at: at(0))
        _ = outbox.deliverNext(at: at(10))

        #expect(outbox.presence(at: at(10)) == .working)
        #expect(outbox.presence(at: at(129.9)) == .working)
        #expect(outbox.presence(at: at(130)) == .absent)
        // Any command of the listener says it's alive.
        outbox.heard(at: at(200))
        #expect(outbox.presence(at: at(319)) == .working)
        // Waiting again while it works: still working, for as long as it waits.
        outbox.waitOpened(by: Self.one, at: at(400))
        #expect(outbox.presence(at: at(4000)) == .working)
        outbox.waitClosed(at: at(4000))
        #expect(outbox.presence(at: at(4119)) == .working)
        #expect(outbox.presence(at: at(4120)) == .absent)

        outbox.heard(at: at(5000))
        outbox.finished(Self.first)
        #expect(outbox.presence(at: at(5001)) == .listening)
        #expect(outbox.presence(at: at(5005)) == .absent)
    }

    @Test("on disk the outbox is its line, what's taken and the session; whether a wait is open belongs to one run")
    func roundTrip() throws {
        var outbox = Outbox()
        outbox.enqueue(Self.first)
        outbox.enqueue(Self.third)
        outbox.waitOpened(by: Self.one, at: at(0))
        _ = outbox.deliverNext(at: at(0))
        outbox.waitOpened(by: Self.one, at: at(1))

        let read = try JSONDecoder().decode(Outbox.self, from: try JSONEncoder().encode(outbox))

        #expect(read.pending == [Self.third])
        #expect(read.taken == [Self.first])
        #expect(read.session == Self.one)
        #expect(!read.isWaitOpen)
        #expect(read.presence(at: at(1)) == .absent)
    }
}
