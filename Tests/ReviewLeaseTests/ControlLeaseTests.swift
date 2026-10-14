import Foundation
import ReviewLease
import Testing

@Suite("The lease")
struct ControlLeaseTests {
    static let a = Holder(key: "CLAUDE_CODE_SESSION_ID=a", name: "Claude Code", place: "/work/shop")
    static let b = Holder(key: "process:300@800250000", name: "codex", place: "Herdr pane w1-2")
    static let c = Holder(key: "operator-c", name: "aider", place: "/work/blog")

    static func at(_ seconds: TimeInterval) -> Date { Date(timeIntervalSince1970: seconds) }

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

    static func name(_ holder: Holder) -> String { holder == a ? "a" : holder == b ? "b" : holder == c ? "c" : holder.key }

    @Test("each operator request in turn takes, renews or is refused the lease", arguments: [
        ([(0.0, a)], ["a until 60 (started a)"]),
        ([(0, a), (30, a), (35, a)], ["a until 60 (started a)", "a until 90 (renewed a)", "a until 95 (renewed a)"]),
        ([(0, a), (55, a), (110, a), (165, a), (220, a), (275, a)],
         ["a until 60 (started a)", "a until 115 (renewed a)", "a until 170 (renewed a)", "a until 225 (renewed a)",
          "a until 280 (renewed a)", "a until 300 (renewed a)"]),
        ([(0, a), (55, a), (110, a), (165, a), (220, a), (275, a), (300, a)],
         ["a until 60 (started a)", "a until 115 (renewed a)", "a until 170 (renewed a)", "a until 225 (renewed a)",
          "a until 280 (renewed a)", "a until 300 (renewed a)", "a until 360 (ended a capped, started a)"]),
        ([(0, a), (30, b), (59, b)], ["a until 60 (started a)", "refused: a until 60", "refused: a until 60"]),
        ([(0, a), (30, b), (60, b)], ["a until 60 (started a)", "refused: a until 60", "b until 120 (ended a expired, started b)"]),
        ([(0, a), (90, a)], ["a until 60 (started a)", "a until 150 (ended a expired, started a)"]),
    ] as [([(TimeInterval, Holder)], [String])])
    func requests(steps: [(TimeInterval, Holder)], expected: [String]) {
        var lease = ControlLease()

        let seen = steps.map { seconds, holder in Self.read(lease.use(by: holder, at: Self.at(seconds))) }

        #expect(seen == expected)
    }

    enum Step: Sendable {
        case use
        case take
        case wait(Int)
        case release
        case giveUp(Int)
        case settle
        case stop
    }

    @Test("take holds to the cap, release frees it, and takes that wait queue first come, first served", arguments: [
        ([(0.0, a, Step.take), (100, a, .use), (300, a, .use)],
         ["a until 300 (started a)", "a until 300 (renewed a)", "a until 360 (ended a capped, started a)"]),
        ([(0, a, .use), (10, a, .take)], ["a until 60 (started a)", "a until 300 (renewed a)"]),
        ([(0, a, .take), (10, b, .take), (20, b, .wait(0))], ["a until 300 (started a)", "refused: a until 300", "refused: a until 300"]),
        ([(0, a, .take), (10, a, .release), (11, b, .use)], ["a until 300 (started a)", "done (ended a released)", "b until 71 (started b)"]),
        ([(0, a, .take), (10, b, .release), (20, b, .use), (30, c, .release)],
         ["a until 300 (started a)", "done", "refused: a until 300", "done"]),
        ([(0, a, .use), (10, b, .wait(100)), (20, c, .wait(100)), (30, a, .release), (40, b, .release)],
         ["a until 60 (started a)", "queued behind a until 60", "queued behind a until 60",
          "done (ended a released, started b)", "done (ended b released, started c)"]),
        ([(0, a, .use), (10, b, .wait(100)), (60, a, .settle), (70, a, .use)],
         ["a until 60 (started a)", "queued behind a until 60", "done (ended a expired, started b)", "refused: b until 360"]),
        ([(0, a, .use), (10, b, .wait(100)), (90, c, .use)],
         ["a until 60 (started a)", "queued behind a until 60", "refused: b until 390 (ended a expired, started b)"]),
        ([(0, a, .use), (10, b, .wait(20)), (30, b, .giveUp(20)), (40, a, .release)],
         ["a until 60 (started a)", "queued behind a until 60", "waited 20s: a until 60", "done (ended a released)"]),
        ([(0, a, .take), (10, b, .wait(20)), (20, c, .wait(100)), (40, a, .release), (40, b, .giveUp(20))],
         ["a until 300 (started a)", "queued behind a until 300", "queued behind a until 300",
          "done (ended a released, started c)", "waited 20s: c until 340"]),
        ([(0, a, .use), (10, b, .wait(50)), (60, b, .giveUp(50))],
         ["a until 60 (started a)", "queued behind a until 60", "b until 360 (ended a expired, started b)"]),
        ([(0, a, .use), (10, b, .wait(20)), (15, c, .wait(100)), (20, b, .wait(100)), (30, b, .giveUp(20)), (40, a, .release)],
         ["a until 60 (started a)", "queued behind a until 60", "queued behind a until 60", "queued behind a until 60",
          "waited 20s: a until 60", "done (ended a released, started b)"]),
    ] as [([(TimeInterval, Holder, Step)], [String])])
    func takes(steps: [(TimeInterval, Holder, Step)], expected: [String]) {
        #expect(Self.run(steps) == expected)
    }

    @Test("the person's Stop ends the holder's lease and bars it for five minutes, and the next waiter gets the lease", arguments: [
        ([(0.0, a, Step.take), (10, a, .stop), (20, a, .use), (30, a, .take), (40, a, .wait(100)), (50, b, .use)],
         ["a until 300 (started a)", "done (ended a stopped)", "refused: stopped", "refused: stopped", "refused: stopped",
          "b until 110 (started b)"]),
        ([(0, a, .use), (10, a, .stop), (309, a, .use), (310, a, .use)],
         ["a until 60 (started a)", "done (ended a stopped)", "refused: stopped", "a until 370 (started a)"]),
        ([(0, a, .take), (10, b, .wait(100)), (20, a, .stop), (30, a, .wait(100)), (40, b, .stop), (50, c, .use)],
         ["a until 300 (started a)", "queued behind a until 300", "done (ended a stopped, started b)", "refused: stopped",
          "done (ended b stopped)", "c until 110 (started c)"]),
        ([(0, a, .use), (10, a, .stop), (310, a, .use), (320, a, .stop), (615, a, .use), (620, a, .use)],
         ["a until 60 (started a)", "done (ended a stopped)", "a until 370 (started a)", "done (ended a stopped)",
          "refused: stopped", "a until 680 (started a)"]),
        ([(0, a, .use), (60, a, .stop), (70, a, .use)], ["a until 60 (started a)", "done (ended a expired)", "a until 130 (started a)"]),
    ] as [([(TimeInterval, Holder, Step)], [String])])
    func stops(steps: [(TimeInterval, Holder, Step)], expected: [String]) {
        #expect(Self.run(steps) == expected)
    }

    static func run(_ steps: [(TimeInterval, Holder, Step)]) -> [String] {
        var lease = ControlLease()
        return steps.map { seconds, holder, step in
            let now = Self.at(seconds)
            switch step {
            case .use: return Self.read(lease.use(by: holder, at: now))
            case .take: return Self.read(lease.take(by: holder, at: now))
            case .wait(let wait):
                return Self.read(lease.take(by: holder, at: now, waitingUntil: now.addingTimeInterval(TimeInterval(wait))))
            case .release: return "done" + Self.read(lease.release(by: holder, at: now))
            case .giveUp(let waited): return Self.read(lease.giveUp(by: holder, waited: waited, at: now))
            case .settle: return "done" + Self.read(lease.settle(at: now))
            case .stop: return "done" + Self.read(lease.stop(at: now))
            }
        }
    }

    @Test("a holder is the same across requests by key, and its latest name and place are kept")
    func sameKey() {
        var lease = ControlLease()
        let moved = Holder(key: Self.a.key, name: "Claude Code", place: "Herdr pane w3-1")

        _ = lease.use(by: Self.a, at: Self.at(0))
        let renewed = lease.use(by: moved, at: Self.at(10))

        #expect(renewed.answer == .success(LeaseTerm(holder: moved, taken: Self.at(0), ends: Self.at(70))))
    }

    @Test("the lease is held until its end, then free; settling ends it once, saying why")
    func expiry() {
        var lease = ControlLease()
        _ = lease.use(by: Self.a, at: Self.at(0))

        #expect(lease.current(at: Self.at(59.9))?.holder == Self.a)
        #expect(lease.settle(at: Self.at(59.9)).isEmpty)
        #expect(lease.current(at: Self.at(60)) == nil)
        #expect(lease.settle(at: Self.at(60)) == [.ended(Self.a, .expired)])
        #expect(lease.settle(at: Self.at(61)).isEmpty)
    }

    @Test("the refusal names the holder, their place, when the lease ends and the seconds left")
    func refusal() throws {
        var lease = ControlLease()
        _ = lease.use(by: Self.b, at: Self.at(0))

        let refused = lease.use(by: Self.a, at: Self.at(12.5))

        guard case .failure(let refusal) = refused.answer else { Issue.record("not refused"); return }
        #expect(refusal.message(at: Self.at(12.5), timeZone: try #require(TimeZone(identifier: "UTC")))
            == "Havooch is in use by codex in Herdr pane w1-2 until 00:01:00 (48s left); "
            + "`havooch control take --timeout <seconds>` to queue")
    }

    @Test("take says until when it holds the lease; a wait that runs out says how long it waited and who still holds it")
    func takeWords() throws {
        let utc = try #require(TimeZone(identifier: "UTC"))
        var lease = ControlLease()
        let held = lease.take(by: Self.b, at: Self.at(0))
        _ = lease.take(by: Self.a, at: Self.at(10), waitingUntil: Self.at(40))

        let waited = lease.giveUp(by: Self.a, waited: 30, at: Self.at(40))

        #expect(try held.answer.get().held(timeZone: utc) == "you hold Havooch until 00:05:00")
        guard case .failure(let refusal) = waited.answer else { Issue.record("not refused"); return }
        #expect(refusal.message(at: Self.at(40), timeZone: utc)
            == "waited 30s; Havooch is still in use by codex in Herdr pane w1-2 until 00:05:00 (260s left)")
    }

    @Test("the stop's refusal tells the agent to ask the person; a bar holds until its end, and the next end is the earliest")
    func stopped() throws {
        var lease = ControlLease()
        _ = lease.take(by: Self.a, at: Self.at(0))
        _ = lease.stop(at: Self.at(10))
        _ = lease.use(by: Self.b, at: Self.at(20))
        _ = lease.stop(at: Self.at(30))
        _ = lease.use(by: Self.c, at: Self.at(40))

        let refused = lease.use(by: Self.a, at: Self.at(50))

        guard case .failure(let refusal) = refused.answer else { Issue.record("not refused"); return }
        #expect(refusal.message(at: Self.at(50), timeZone: try #require(TimeZone(identifier: "UTC")))
            == "the person took Havooch back; ask them before using it again")
        #expect(lease.nextEnd(after: Self.at(50)) == Self.at(100))
        _ = lease.release(by: Self.c, at: Self.at(60))
        #expect(lease.nextEnd(after: Self.at(60)) == Self.at(310))
        #expect(lease.nextEnd(after: Self.at(310)) == Self.at(330))
        #expect(lease.nextEnd(after: Self.at(330)) == nil)
    }

    @Test("the status reports the held lease's holder, times, whole seconds left and waiters, and nothing once it's free")
    func status() {
        var lease = ControlLease()
        #expect(lease.status(at: Self.at(0)) == nil)
        _ = lease.use(by: Self.a, at: Self.at(0))

        #expect(lease.status(at: Self.at(12.5))
            == ControlLease.Status(holder: Self.a, taken: Self.at(0), ends: Self.at(60), secondsLeft: 48, waiting: 0))
        _ = lease.take(by: Self.b, at: Self.at(20), waitingUntil: Self.at(50))
        _ = lease.take(by: Self.c, at: Self.at(30), waitingUntil: Self.at(90))
        #expect(lease.status(at: Self.at(30))?.waiting == 2)
        #expect(lease.status(at: Self.at(50))?.waiting == 1)
        #expect(lease.status(at: Self.at(60)) == nil)
    }

    static func handover(taken: TimeInterval, ends: TimeInterval) -> String {
        ControlLease.handover(LeaseTerm(holder: a, taken: at(taken), ends: at(ends)))[ControlLease.handoverVariable] ?? ""
    }

    @Test("a relaunch hands the lease over in HAVOOCH_CONTROL_LEASE")
    func handoverForm() {
        let term = LeaseTerm(holder: Self.a, taken: Self.at(0), ends: Self.at(70.5))

        let handed = ControlLease.handover(term)

        #expect(Array(handed.keys) == ["HAVOOCH_CONTROL_LEASE"])
        #expect(ControlLease(environment: handed, at: Self.at(10)).current(at: Self.at(10)) == term)
    }

    @Test("an app launched with a handed-over lease holds it: it refuses another holder and keeps the original cap")
    func handedOver() {
        var lease = ControlLease(environment: [ControlLease.handoverVariable: Self.handover(taken: 0, ends: 280)], at: Self.at(250))

        #expect(lease.current(at: Self.at(250)) == LeaseTerm(holder: Self.a, taken: Self.at(0), ends: Self.at(280)))
        let seen = [(260.0, Self.b), (270, Self.a), (300, Self.b)].map { seconds, holder in
            Self.read(lease.use(by: holder, at: Self.at(seconds)))
        }
        #expect(seen == ["refused: a until 280", "a until 300 (renewed a)", "b until 360 (ended a capped, started b)"])
    }

    @Test("a handover that has ended, whose end past its cap has passed, or that doesn't read leaves the launched app's lease free",
          arguments: [
              (ControlLeaseTests.handover(taken: 0, ends: 60), 60.0),
              (ControlLeaseTests.handover(taken: 0, ends: 900), 300),
              (#"{"holder":{"key":"k","name":"n","place":"p"}}"#, 0),
              ("", 0),
          ] as [(String, TimeInterval)])
    func handoverIgnored(json: String, seconds: TimeInterval) {
        let lease = ControlLease(environment: [ControlLease.handoverVariable: json], at: Self.at(seconds))

        #expect(lease == ControlLease())
    }

    @Test("an app launched without a handover starts free")
    func noHandover() {
        #expect(ControlLease(environment: [:], at: Self.at(0)) == ControlLease())
    }
}
