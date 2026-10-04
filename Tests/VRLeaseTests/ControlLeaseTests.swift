import Foundation
import Testing
import VRLease

/// The lease's rules as tables: what each holder does at which second of a
/// clock the test owns, and what each step got.
@Suite struct ControlLeaseTests {
    static let a = Holder(key: "CLAUDE_CODE_SESSION_ID=a", name: "Claude Code", place: "/work/shop")
    static let b = Holder(key: "process:300@800250000", name: "codex", place: "Herdr pane w1-2")
    static let c = Holder(key: "second agent", name: "aider", place: "/work/blog")

    static func at(_ seconds: TimeInterval) -> Date { Date(timeIntervalSince1970: seconds) }

    /// What a holder does at one step.
    enum Step: Sendable {
        /// Any operator command (`player play`).
        case use
        /// `control take`.
        case take
        /// `control take --wait <seconds>`.
        case wait(Int)
        /// `control release`.
        case release
        /// A waiting `take`'s wait of so many seconds runs out.
        case giveUp(Int)
        /// The app settles the lease when its end comes.
        case settle
        /// The person's Stop, on whoever holds the lease.
        case stop
    }

    /// What each step got, from a lease free at the start.
    static func run(_ steps: [(TimeInterval, Holder, Step)]) -> [String] {
        var lease = ControlLease()
        return steps.map { seconds, holder, step in
            let now = at(seconds)
            switch step {
            case .use: return read(lease.use(by: holder, at: now))
            case .take: return read(lease.take(by: holder, at: now))
            case .wait(let wait): return read(lease.take(by: holder, at: now, waitingUntil: now.addingTimeInterval(TimeInterval(wait))))
            case .release: return "done" + read(lease.release(by: holder, at: now))
            case .giveUp(let waited): return read(lease.giveUp(by: holder, waited: waited, at: now))
            case .settle: return "done" + read(lease.settle(at: now))
            case .stop: return "done" + read(lease.stop(at: now))
            }
        }
    }

    /// A decision as one line: `a until 60 (started a)`, `refused: a until
    /// 60`, `queued behind a until 60`, `waited 20s: a until 60` or
    /// `refused: stopped`.
    static func read(_ decision: ControlLease.Decision) -> String {
        let answer = switch decision.answer {
        case .success(let term): "\(name(term.holder)) until \(Int(term.ends.timeIntervalSince1970))"
        case .failure(.inUse(let term)): "refused: \(name(term.holder)) until \(Int(term.ends.timeIntervalSince1970))"
        case .failure(.queued(let term)): "queued behind \(name(term.holder)) until \(Int(term.ends.timeIntervalSince1970))"
        case .failure(.waitedOut(let seconds, let term)):
            "waited \(seconds)s: \(name(term.holder)) until \(Int(term.ends.timeIntervalSince1970))"
        case .failure(.stopped): "refused: stopped"
        }
        return answer + read(decision.transitions)
    }

    /// Transitions as ` (ended a released, started b)`, or nothing.
    static func read(_ transitions: [ControlLease.Transition]) -> String {
        let lines = transitions.map { transition in
            switch transition {
            case .started(let holder): "started \(name(holder))"
            case .renewed(let holder): "renewed \(name(holder))"
            case .ended(let holder, let ending): "ended \(name(holder)) \(ending)"
            }
        }
        return lines.isEmpty ? "" : " (\(lines.joined(separator: ", ")))"
    }

    static func name(_ holder: Holder) -> String {
        holder.key == a.key ? "a" : holder.key == b.key ? "b" : holder.key == c.key ? "c" : holder.key
    }

    // MARK: - Operator commands

    @Test(arguments: [
        // The first operator command takes the lease for a minute.
        ([(0.0, a, Step.use)], ["a until 60 (started a)"]),
        // Each command renews it to a minute from then.
        ([(0, a, .use), (30, a, .use), (35, a, .use)], ["a until 60 (started a)", "a until 90 (renewed a)", "a until 95 (renewed a)"]),
        // Renewal stops at the cap, five minutes after it was taken.
        ([(0, a, .use), (55, a, .use), (110, a, .use), (165, a, .use), (220, a, .use), (275, a, .use)],
         ["a until 60 (started a)", "a until 115 (renewed a)", "a until 170 (renewed a)", "a until 225 (renewed a)",
          "a until 280 (renewed a)", "a until 300 (renewed a)"]),
        // At the cap it ends, however busy its holder; the holder's next command takes a new one.
        ([(0, a, .use), (55, a, .use), (110, a, .use), (165, a, .use), (220, a, .use), (275, a, .use), (299, a, .use), (300, a, .use)],
         ["a until 60 (started a)", "a until 115 (renewed a)", "a until 170 (renewed a)", "a until 225 (renewed a)",
          "a until 280 (renewed a)", "a until 300 (renewed a)", "a until 300 (renewed a)", "a until 360 (ended a capped, started a)"]),
        // Another holder is refused while it's held, and the refusal renews nothing.
        ([(0, a, .use), (30, b, .use), (59, b, .use)], ["a until 60 (started a)", "refused: a until 60", "refused: a until 60"]),
        // A minute after the holder's last command it's free: anyone takes it.
        ([(0, a, .use), (30, b, .use), (60, b, .use)],
         ["a until 60 (started a)", "refused: a until 60", "b until 120 (ended a expired, started b)"]),
        // Once ended, its holder takes it again like anyone.
        ([(0, a, .use), (90, a, .use)], ["a until 60 (started a)", "a until 150 (ended a expired, started a)"]),
    ] as [([(TimeInterval, Holder, Step)], [String])])
    func eachOperatorCommandTakesRenewsOrIsRefusedTheLease(steps: [(TimeInterval, Holder, Step)], expected: [String]) {
        #expect(Self.run(steps) == expected)
    }

    // MARK: - Take, release and the line

    @Test(arguments: [
        // Take holds the lease to the cap; commands don't shorten it, and it ends there.
        ([(0.0, a, Step.take), (100, a, .use), (299, b, .use), (300, a, .use)],
         ["a until 300 (started a)", "a until 300 (renewed a)", "refused: a until 300", "a until 360 (ended a capped, started a)"]),
        // Take after an implicit lease holds it to that lease's cap, not to a new one.
        ([(0, a, .use), (10, a, .take)], ["a until 60 (started a)", "a until 300 (renewed a)"]),
        // Take from another holder, without a wait or with none left, is refused at once.
        ([(0, a, .take), (10, b, .take), (20, b, .wait(0))], ["a until 300 (started a)", "refused: a until 300", "refused: a until 300"]),
        // The holder's release frees it; anyone takes it next.
        ([(0, a, .take), (10, a, .release), (11, b, .use)],
         ["a until 300 (started a)", "done (ended a released)", "b until 71 (started b)"]),
        // Release from anyone else, or while it's free, changes nothing.
        ([(0, a, .take), (10, b, .release), (20, b, .use), (30, a, .release), (40, c, .release)],
         ["a until 300 (started a)", "done", "refused: a until 300", "done (ended a released)", "done"]),
        // Waiters queue first come, first served: each release hands it to the next, held to its cap.
        ([(0, a, .use), (10, b, .wait(100)), (20, c, .wait(100)), (30, a, .release), (40, b, .release)],
         ["a until 60 (started a)", "queued behind a until 60", "queued behind a until 60",
          "done (ended a released, started b)", "done (ended b released, started c)"]),
        // A lease that runs out hands it to the first waiter when the app settles it.
        ([(0, a, .use), (10, b, .wait(100)), (60, a, .settle), (70, a, .use)],
         ["a until 60 (started a)", "queued behind a until 60", "done (ended a expired, started b)", "refused: b until 360"]),
        // A command that comes after it ran out finds the waiter holding it.
        ([(0, a, .use), (10, b, .wait(100)), (90, c, .use)],
         ["a until 60 (started a)", "queued behind a until 60", "refused: b until 390 (ended a expired, started b)"]),
        // A wait that runs out is refused with the lease as it stands, and the line is empty after.
        ([(0, a, .use), (10, b, .wait(20)), (30, b, .giveUp(20)), (40, a, .release)],
         ["a until 60 (started a)", "queued behind a until 60", "waited 20s: a until 60", "done (ended a released)"]),
        // A waiter whose wait ran out is passed over for the next.
        ([(0, a, .take), (10, b, .wait(20)), (20, c, .wait(100)), (40, a, .release), (40, b, .giveUp(20))],
         ["a until 300 (started a)", "queued behind a until 300", "queued behind a until 300",
          "done (ended a released, started c)", "waited 20s: c until 340"]),
        // A wait that runs out as the lease frees takes it, as it asked to.
        ([(0, a, .use), (10, b, .wait(50)), (60, b, .giveUp(50))],
         ["a until 60 (started a)", "queued behind a until 60", "b until 360 (ended a expired, started b)"]),
        // A holder queuing twice keeps its first place and waits until the later deadline.
        ([(0, a, .use), (10, b, .wait(20)), (15, c, .wait(100)), (20, b, .wait(100)), (30, b, .giveUp(20)), (40, a, .release)],
         ["a until 60 (started a)", "queued behind a until 60", "queued behind a until 60", "queued behind a until 60",
          "waited 20s: a until 60", "done (ended a released, started b)"]),
    ] as [([(TimeInterval, Holder, Step)], [String])])
    func takeHoldsToTheCapReleaseFreesItAndWaitingTakesQueueInOrder(steps: [(TimeInterval, Holder, Step)], expected: [String]) {
        #expect(Self.run(steps) == expected)
    }

    // MARK: - The person's Stop

    @Test(arguments: [
        // Stop ends the lease; the stopped holder's commands, take and waiting take are refused, and nobody else's.
        ([(0.0, a, Step.take), (10, a, .stop), (20, a, .use), (30, a, .take), (40, a, .wait(100)), (50, b, .use)],
         ["a until 300 (started a)", "done (ended a stopped)", "refused: stopped", "refused: stopped", "refused: stopped",
          "b until 110 (started b)"]),
        // The bar lasts five minutes from the stop, then the holder takes the lease like anyone.
        ([(0, a, .use), (10, a, .stop), (309, a, .use), (310, a, .use)],
         ["a until 60 (started a)", "done (ended a stopped)", "refused: stopped", "a until 370 (started a)"]),
        // The next waiter gets the lease at once, held to its cap; the stopped holder can't queue behind it.
        ([(0, a, .take), (10, b, .wait(100)), (20, a, .stop), (30, a, .wait(100)), (40, b, .stop), (50, c, .use)],
         ["a until 300 (started a)", "queued behind a until 300", "done (ended a stopped, started b)", "refused: stopped",
          "done (ended b stopped)", "c until 110 (started c)"]),
        // A second stop of the same holder bars it for five minutes from the later one.
        ([(0, a, .use), (10, a, .stop), (310, a, .use), (320, a, .stop), (619, a, .use), (620, a, .use)],
         ["a until 60 (started a)", "done (ended a stopped)", "a until 370 (started a)", "done (ended a stopped)",
          "refused: stopped", "a until 680 (started a)"]),
        // Stop after the lease ran out, or while it's free, ends nothing and bars nobody.
        ([(0, a, .use), (60, a, .stop), (70, a, .use), (200, a, .stop), (210, b, .use)],
         ["a until 60 (started a)", "done (ended a expired)", "a until 130 (started a)", "done (ended a expired)",
          "b until 270 (started b)"]),
    ] as [([(TimeInterval, Holder, Step)], [String])])
    func stopEndsTheLeaseBarsItsHolderForFiveMinutesAndHandsItToTheNextWaiter(steps: [(TimeInterval, Holder, Step)], expected: [String]) {
        #expect(Self.run(steps) == expected)
    }

    // MARK: - Single rules

    @Test func aHolderIsTheSameAcrossCommandsByItsKeyAndItsLatestNameAndPlaceAreKept() {
        var lease = ControlLease()
        let moved = Holder(key: Self.a.key, name: "Claude Code", place: "Herdr pane w3-1")

        _ = lease.use(by: Self.a, at: Self.at(0))
        let renewed = lease.use(by: moved, at: Self.at(10))

        #expect(renewed.answer == .success(ControlLease.Term(holder: moved, taken: Self.at(0), ends: Self.at(70))))
    }

    @Test func theLeaseIsHeldUntilItsEndThenFreeAndSettlingEndsItOnce() {
        var lease = ControlLease()
        _ = lease.use(by: Self.a, at: Self.at(0))

        #expect(lease.current(at: Self.at(59.9))?.holder == Self.a)
        #expect(lease.nextEnd(after: Self.at(59.9)) == Self.at(60))
        #expect(lease.settle(at: Self.at(59.9)).isEmpty)
        #expect(lease.current(at: Self.at(60)) == nil)
        #expect(lease.nextEnd(after: Self.at(60)) == nil)
        #expect(lease.settle(at: Self.at(60)) == [.ended(Self.a, .expired)])
        #expect(lease.settle(at: Self.at(61)).isEmpty)
    }

    @Test func theRefusalNamesTheHolderItsPlaceTheEndOfTheLeaseAndTheSecondsLeft() throws {
        let utc = try #require(TimeZone(identifier: "UTC"))
        var lease = ControlLease()
        _ = lease.use(by: Self.b, at: Self.at(0))

        let refused = lease.use(by: Self.a, at: Self.at(12.5))

        guard case .failure(let refusal) = refused.answer else { Issue.record("not refused"); return }
        #expect(refusal.message(at: Self.at(12.5), timeZone: utc)
            == "video-review is in use by codex in Herdr pane w1-2 until 00:01:00 (48s left); "
            + "`video-review control take --wait <seconds>` to queue")
        // The end is told in the zone asked for.
        #expect(refusal.message(at: Self.at(12.5), timeZone: try #require(TimeZone(secondsFromGMT: 3 * 3600)))
            .contains("until 03:01:00 (48s left)"))
    }

    @Test func takeSaysUntilWhenItHoldsTheLeaseAndAWaitThatRunsOutSaysHowLongItWaited() throws {
        let utc = try #require(TimeZone(identifier: "UTC"))
        var lease = ControlLease()
        let held = lease.take(by: Self.b, at: Self.at(0))
        _ = lease.take(by: Self.a, at: Self.at(10), waitingUntil: Self.at(40))

        let waited = lease.giveUp(by: Self.a, waited: 30, at: Self.at(40))

        #expect(try held.answer.get().held(timeZone: utc) == "you hold video-review until 00:05:00")
        guard case .failure(let refusal) = waited.answer else { Issue.record("not refused"); return }
        #expect(refusal.message(at: Self.at(40), timeZone: utc)
            == "waited 30s; video-review is still in use by codex in Herdr pane w1-2 until 00:05:00 (260s left)")
    }

    @Test func theStopsRefusalTellsTheAgentToAskThePerson() throws {
        var lease = ControlLease()
        _ = lease.take(by: Self.a, at: Self.at(0))
        _ = lease.stop(at: Self.at(10))

        let refused = lease.use(by: Self.a, at: Self.at(50))

        guard case .failure(let refusal) = refused.answer else { Issue.record("not refused"); return }
        #expect(refusal.message(at: Self.at(50), timeZone: try #require(TimeZone(identifier: "UTC")))
            == "the person took video-review back; ask them before using it again")
        #expect(lease.current(at: Self.at(50)) == nil)
    }

    @Test func theStatusReportsTheHolderItsPlaceWholeSecondsLeftAndTheWaiters() {
        var lease = ControlLease()
        #expect(lease.status(at: Self.at(0)) == nil)
        _ = lease.use(by: Self.a, at: Self.at(0))

        #expect(lease.status(at: Self.at(12.5)) == ControlLease.Status(holder: "Claude Code", place: "/work/shop", secondsLeft: 48, waiting: 0))
        _ = lease.take(by: Self.b, at: Self.at(20), waitingUntil: Self.at(50))
        _ = lease.take(by: Self.c, at: Self.at(30), waitingUntil: Self.at(90))
        // Waiters count while their waits haven't run out.
        #expect(lease.status(at: Self.at(30))?.waiting == 2)
        #expect(lease.status(at: Self.at(50))?.waiting == 1)
        #expect(lease.status(at: Self.at(60)) == nil)
    }

    // MARK: - A relaunch's handover

    /// The handover's variables for `a`'s lease, taken at `taken` and ending at `ends`.
    static func handover(taken: TimeInterval, ends: TimeInterval) -> [String: String] {
        ControlLease.handover(ControlLease.Term(holder: a, taken: at(taken), ends: at(ends)))
    }

    @Test func anAppLaunchedWithAHandedOverLeaseHoldsItAndKeepsTheFirstCap() {
        // Taken at 0 by the app that quit and renewed to 280; the launched app reads it at 250.
        var lease = ControlLease(environment: Self.handover(taken: 0, ends: 280), at: Self.at(250))

        #expect(lease.current(at: Self.at(250)) == ControlLease.Term(holder: Self.a, taken: Self.at(0), ends: Self.at(280)))
        let seen = [(260.0, Self.b), (270, Self.a), (300, Self.b)].map { seconds, holder in
            Self.read(lease.use(by: holder, at: Self.at(seconds)))
        }
        #expect(seen == ["refused: a until 280", "a until 300 (renewed a)", "b until 360 (ended a capped, started b)"])
    }

    @Test(arguments: [
        // It has ended.
        (ControlLeaseTests.handover(taken: 0, ends: 60), 60.0),
        // Its end is past its cap, and the cap has passed.
        (ControlLeaseTests.handover(taken: 0, ends: 900), 300),
        // It doesn't read.
        ([ControlLease.handoverVariable: #"{"holder":{"key":"k","name":"n","place":"p"}}"#], 0),
        ([ControlLease.handoverVariable: ""], 0),
        // There's none.
        ([:], 0),
    ] as [([String: String], TimeInterval)])
    func aHandoverThatHasEndedOrDoesNotReadLeavesTheLeaseFree(environment: [String: String], seconds: TimeInterval) {
        #expect(ControlLease(environment: environment, at: Self.at(seconds)) == ControlLease())
    }

    @Test func aHandoverPastItsCapIsCutToTheCap() {
        let lease = ControlLease(environment: Self.handover(taken: 0, ends: 900), at: Self.at(100))

        #expect(lease.current(at: Self.at(100))?.ends == Self.at(300))
    }
}
