import Foundation
import ReviewCore
import Testing

/// The listener's outbox, driven by the time the test gives it.
@Suite("The listener's outbox")
struct OutboxTests {
    static let first = SendRef(sendID: ItemID("s-00000000-1")!, contentHash: "abc")
    static let second = SendRef(sendID: ItemID("s-00000000-2")!, contentHash: "abc")
    static let third = SendRef(sendID: ItemID("s-00000000-3")!, contentHash: "def")
    static let one = ListenerSession(key: "listener-1", name: "Claude Code", place: "/work")
    static let two = ListenerSession(key: "listener-2", name: "Claude Code", place: "/work")

    private func at(_ seconds: TimeInterval) -> Date { Date(timeIntervalSince1970: seconds) }

    @Test("a send made while a wait is open is delivered to it, and is taken from then on")
    func deliversToTheOpenWait() {
        var outbox = Outbox()
        outbox.waitOpened(by: Self.one, at: at(0))
        #expect(outbox.deliverNext(at: at(0)) == nil)

        outbox.enqueue(Self.first)
        #expect(outbox.deliverNext(at: at(5)) == Self.first)

        #expect(outbox.pending.isEmpty)
        #expect(outbox.taken == [Self.first])
        // The wait was answered: the next send needs the next wait.
        #expect(!outbox.isWaitOpen)
        outbox.enqueue(Self.second)
        #expect(outbox.deliverNext(at: at(6)) == nil)
        #expect(outbox.pending == [Self.second])
    }

    @Test("a send made with no listener waits, and the next wait gets it; sends go out first in, first out, one per wait")
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

    @Test("a send is in line once")
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

    @Test("a wait from another holder is a new listener session: the taken sends are first in line again, in the order taken")
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

    @Test("a wait from the same holder keeps what it took: the listener waits again before it works on a send")
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

    @Test("a send whose reply couldn't be written is first in line again; a finished one is gone")
    func undeliveredAndFinished() {
        var outbox = Outbox()
        outbox.enqueue(Self.first)
        outbox.enqueue(Self.second)
        outbox.waitOpened(by: Self.one, at: at(0))
        _ = outbox.deliverNext(at: at(0))

        outbox.undelivered(Self.first)
        #expect(outbox.taken.isEmpty)
        #expect(outbox.pending == [Self.first, Self.second])
        // Only a taken send goes back.
        outbox.undelivered(Self.third)
        #expect(outbox.pending == [Self.first, Self.second])

        outbox.waitOpened(by: Self.one, at: at(1))
        _ = outbox.deliverNext(at: at(1))
        outbox.finished(Self.first)
        #expect(outbox.taken.isEmpty)
        // A finished send isn't requeued for the next session.
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

    @Test("presence is working while a send is taken and the listener was heard in the last 120 s or waits again")
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

    @Test("an outbox written with a key missing reads with that part empty")
    func missingKeys() throws {
        let read = try JSONDecoder().decode(Outbox.self, from: Data("""
        { "pending": [ { "sendID": "s-00000000-1", "contentHash": "abc" } ], "taken": [] }
        """.utf8))
        #expect(read.pending == [Self.first])
        #expect(read.session == nil)
        #expect(read.contextSent.isEmpty)
        #expect(try JSONDecoder().decode(Outbox.self, from: Data("{}".utf8)) == Outbox())
    }

    @Test("after a restart, a taken send stays with the same listener and goes back in line for a new one")
    func takenAcrossARestart() throws {
        var outbox = Outbox()
        outbox.enqueue(Self.first)
        outbox.waitOpened(by: Self.one, at: at(0))
        _ = outbox.deliverNext(at: at(0))

        var same = try JSONDecoder().decode(Outbox.self, from: try JSONEncoder().encode(outbox))
        #expect(same.waitOpened(by: Self.one, at: at(60)).isEmpty)
        #expect(same.taken == [Self.first])
        #expect(same.deliverNext(at: at(60)) == nil)

        var new = try JSONDecoder().decode(Outbox.self, from: try JSONEncoder().encode(outbox))
        #expect(new.waitOpened(by: Self.two, at: at(60)) == [Self.first])
        #expect(new.deliverNext(at: at(60)) == Self.first)
    }

    @Test("at launch the outbox is made to agree with the reviews: a send that's gone or finished leaves, an unfinished one that's missing joins the line")
    func reconcile() {
        var outbox = Outbox()
        outbox.enqueue(Self.first)
        outbox.enqueue(Self.second)
        outbox.waitOpened(by: Self.one, at: at(0))
        _ = outbox.deliverNext(at: at(0))
        let before = outbox

        // All is as the reviews say: nothing moves.
        outbox.reconcile(unfinished: [Self.first, Self.second])
        #expect(outbox == before)
        #expect(outbox.isKeptAs(before))

        // The taken send was finished and the outbox wasn't saved after;
        // a send was made and the outbox wasn't saved after.
        outbox.reconcile(unfinished: [Self.second, Self.third])
        #expect(outbox.taken.isEmpty)
        #expect(outbox.pending == [Self.second, Self.third])
        #expect(!outbox.isKeptAs(before))

        outbox.reconcile(unfinished: [])
        #expect(outbox.pending.isEmpty)
        #expect(outbox.session == Self.one)
    }

    @Test("what's kept is the line, the taken sends, the session and the context sent; not the open wait or the last word")
    func whatIsKept() {
        var outbox = Outbox()
        let empty = outbox
        outbox.heard(at: at(5))
        outbox.askOpened(at: at(6))
        #expect(outbox.isKeptAs(empty))
        outbox.waitOpened(by: Self.one, at: at(7))
        #expect(!outbox.isKeptAs(empty))
        let listening = outbox
        outbox.waitClosed(at: at(8))
        #expect(outbox.isKeptAs(listening))
        _ = outbox.context(for: "abc", text: "About")
        #expect(!outbox.isKeptAs(listening))
    }
}
