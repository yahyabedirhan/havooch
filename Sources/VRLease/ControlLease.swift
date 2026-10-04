import Foundation

/// App control's lease: who may send operator commands, and until when. One
/// agent at a time holds it. An operator command from the holder, or from
/// anyone while it's free, takes or renews it; one from another holder is
/// refused. It ends by itself `renewal` after the holder's last command, and
/// `cap` after it was taken at most, so a crashed agent can't keep it.
/// `control take` holds it to the cap on purpose and `control release` gives
/// it up. A `take` that may wait queues behind the holder, first come, first
/// served, and the first waiter whose wait hasn't run out gets the lease
/// when it frees. The person's Stop ends the lease and bars its holder for
/// `bar`.
///
/// A pure value, given the time on each call: the app owns the one instance
/// and drives it, and its answers and transitions are all it needs to
/// refuse and redraw. The rules are Shipyard's `ControlLease`.
public struct ControlLease: Equatable, Sendable {
    /// How long after the holder's last command the lease ends.
    public static let renewal: TimeInterval = 60
    /// How long after it was taken the lease ends, however it's renewed.
    public static let cap: TimeInterval = 5 * 60
    /// How long a holder the person stopped is refused.
    public static let bar: TimeInterval = 5 * 60

    /// One holding of the lease: by whom, since when, and when it ends.
    public struct Term: Equatable, Sendable {
        public var holder: Holder
        public var taken: Date
        public var ends: Date

        public init(holder: Holder, taken: Date, ends: Date) {
            self.holder = holder
            self.taken = taken
            self.ends = ends
        }

        /// The latest it can end, however it's renewed.
        public var capped: Date { taken.addingTimeInterval(ControlLease.cap) }

        /// Whole seconds left at `now`, rounded up: 0 once it has ended.
        public func secondsLeft(at now: Date) -> Int {
            max(0, Int(ends.timeIntervalSince(now).rounded(.up)))
        }

        /// What `control take` prints once it holds the lease, its end in
        /// `timeZone`: `you hold video-review until 12:05:00`.
        public func held(timeZone: TimeZone) -> String {
            "you hold video-review until \(ControlLease.clock(ends, timeZone))"
        }
    }

    /// A change in who holds the lease, for the app to follow.
    public enum Transition: Equatable, Sendable {
        case started(Holder)
        case renewed(Holder)
        case ended(Holder, Ending)
    }

    /// Why a lease ended.
    public enum Ending: Equatable, Sendable {
        /// Its holder sent nothing for `renewal`.
        case expired
        /// It reached `cap`.
        case capped
        /// Its holder gave it up (`control release`).
        case released
        /// The person took the app back (the banner's Stop).
        case stopped
    }

    /// Why a holder may not act.
    public enum Refusal: Error, Equatable, Sendable {
        /// Another holder has the lease.
        case inUse(Term)
        /// Another holder has the lease, and the `take` waits in line behind
        /// it: no answer yet, until it gets the lease or its wait runs out.
        case queued(Term)
        /// The `take` waited its `seconds` in line, and another holder still
        /// has the lease.
        case waitedOut(seconds: Int, Term)
        /// The person stopped this holder, and its bar hasn't ended.
        case stopped

        /// One line for the reply's `error`, its times in `timeZone`.
        public func message(at now: Date, timeZone: TimeZone) -> String {
            switch self {
            case .stopped:
                return "the user took video-review back; ask them before using it again"
            case .inUse(let term), .queued(let term):
                return "video-review is in use by \(term.holder.name) in \(term.holder.place) until \(clock(term.ends, timeZone)) "
                    + "(\(term.secondsLeft(at: now))s left); `video-review control take --wait <seconds>` to queue"
            case .waitedOut(let seconds, let term):
                return "waited \(seconds)s; video-review is still in use by \(term.holder.name) in \(term.holder.place) "
                    + "until \(clock(term.ends, timeZone)) (\(term.secondsLeft(at: now))s left)"
            }
        }
    }

    /// `date` as the agent reads it in `timeZone`: `12:05:00`.
    static func clock(_ date: Date, _ timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }

    /// The lease's answer to one call, and what changed on the way.
    public struct Decision: Equatable, Sendable {
        /// The term the call acts under, or why it may not.
        public var answer: Result<Term, Refusal>
        /// In order: a lease that ran out ends before the next one starts.
        public var transitions: [Transition]

        public init(answer: Result<Term, Refusal>, transitions: [Transition] = []) {
            self.answer = answer
            self.transitions = transitions
        }
    }

    /// A `take` waiting in line: who, and until when it waits.
    private struct Waiter: Equatable, Sendable {
        var holder: Holder
        var until: Date
    }

    /// A holder the person stopped, refused until `until`.
    private struct Bar: Equatable, Sendable {
        var key: String
        var until: Date
    }

    /// The lease as of the last call; it may have ended since, so it's read
    /// through `current(at:)`.
    private var term: Term?
    /// The `take`s waiting for the lease, first come first: one place per
    /// holder key.
    private var queue: [Waiter] = []
    /// The holders the person stopped: one per holder key.
    private var bars: [Bar] = []

    public init() {}

    /// The lease an app launched with `environment` starts with at `now`:
    /// the one a relaunch handed over in `handoverVariable`, keeping when it
    /// was taken and so its cap, and posting no transition; free when
    /// there's none, it doesn't read, or it has already ended.
    public init(environment: [String: String], at now: Date) {
        guard let json = environment[Self.handoverVariable],
              var term = try? JSONDecoder().decode(Term.self, from: Data(json.utf8)) else { return }
        term.ends = min(term.ends, term.capped)
        guard now < term.ends else { return }
        self.term = term
    }

    /// The launch environment's variable a relaunch hands the lease over in.
    public static let handoverVariable = "VIDEO_REVIEW_CONTROL_LEASE"

    /// What a relaunch adds to the launched app's environment to hand `term`
    /// over: `handoverVariable`, as one small JSON object,
    /// `{"ends":<seconds since 1970>,"holder":{…},"taken":<seconds since 1970>}`.
    public static func handover(_ term: Term) -> [String: String] {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        // Encoding strings and numbers can't fail.
        return [handoverVariable: String(decoding: try! encoder.encode(term), as: UTF8.self)]
    }

    /// The term that holds at `now`, or nil when the lease is free.
    public func current(at now: Date) -> Term? {
        guard let term, now < term.ends else { return nil }
        return term
    }

    /// How many `take`s wait in line at `now`, their waits not run out.
    public func waiting(at now: Date) -> Int {
        queue.filter { now < $0.until }.count
    }

    /// Lifts the bars that have ended by `now`, ends a lease that has run
    /// out by then, and hands a free lease to the first waiter whose wait
    /// hasn't run out, as a `take` does: the transitions, none when nothing
    /// changed. The app also calls it at `nextEnd(after:)`, so a waiter gets
    /// the lease without another request.
    public mutating func settle(at now: Date) -> [Transition] {
        var transitions: [Transition] = []
        bars.removeAll { now >= $0.until }
        if let term, now >= term.ends {
            self.term = nil
            transitions.append(.ended(term.holder, term.ends >= term.capped ? .capped : .expired))
        }
        guard term == nil else { return transitions }
        // A wait that ran out leaves the line; its `take` is refused as such.
        queue.removeAll { now >= $0.until }
        guard !queue.isEmpty else { return transitions }
        let next = queue.removeFirst()
        term = Term(holder: next.holder, taken: now, ends: now.addingTimeInterval(Self.cap))
        transitions.append(.started(next.holder))
        return transitions
    }

    /// An operator command by `holder` at `now`: granted when `holder` holds
    /// the lease (renewing it to `renewal` from now, never past the cap), or
    /// when it's free (taking it); refused while another holds it, or while
    /// `holder` is barred.
    public mutating func use(by holder: Holder, at now: Date) -> Decision {
        var transitions = settle(at: now)
        // A barred holder never holds the lease: Stop ended it.
        guard !isBarred(holder) else { return Decision(answer: .failure(.stopped), transitions: transitions) }
        if var term {
            guard term.holder.key == holder.key else {
                return Decision(answer: .failure(.inUse(term)), transitions: transitions)
            }
            term.ends = min(max(term.ends, now.addingTimeInterval(Self.renewal)), term.capped)
            // The holder's name and place are as its latest command says.
            term.holder = holder
            self.term = term
            transitions.append(.renewed(holder))
            return Decision(answer: .success(term), transitions: transitions)
        }
        let term = Term(holder: holder, taken: now, ends: now.addingTimeInterval(Self.renewal))
        self.term = term
        transitions.append(.started(holder))
        return Decision(answer: .success(term), transitions: transitions)
    }

    /// `control take` from `holder` at `now`: when `holder` holds the lease,
    /// or it's free, it's held until the cap (`renewed` or `started`). While
    /// another holds it, the `take` waits in line until `deadline` (`queued`:
    /// a holder already in line keeps its place and waits until the later
    /// deadline), or is refused at once without a deadline after `now`. A
    /// barred holder is refused at once, wait or not, so it never joins the
    /// line.
    public mutating func take(by holder: Holder, at now: Date, waitingUntil deadline: Date? = nil) -> Decision {
        var transitions = settle(at: now)
        guard !isBarred(holder) else { return Decision(answer: .failure(.stopped), transitions: transitions) }
        guard var term else {
            let term = Term(holder: holder, taken: now, ends: now.addingTimeInterval(Self.cap))
            self.term = term
            transitions.append(.started(holder))
            return Decision(answer: .success(term), transitions: transitions)
        }
        guard term.holder.key == holder.key else {
            guard let deadline, now < deadline else {
                return Decision(answer: .failure(.inUse(term)), transitions: transitions)
            }
            if let place = queue.firstIndex(where: { $0.holder.key == holder.key }) {
                queue[place].holder = holder
                queue[place].until = max(queue[place].until, deadline)
            } else {
                queue.append(Waiter(holder: holder, until: deadline))
            }
            return Decision(answer: .failure(.queued(term)), transitions: transitions)
        }
        term.ends = term.capped
        term.holder = holder
        self.term = term
        transitions.append(.renewed(holder))
        return Decision(answer: .success(term), transitions: transitions)
    }

    /// The end of a `take` from `holder` that waited `seconds` in line, at
    /// `now`, when its wait runs out: it leaves the line once its wait (the
    /// later deadline, should it have queued twice) has run out, and is
    /// refused with the lease as it stands. Should the lease be free by
    /// then, it takes it, as it asked to.
    public mutating func giveUp(by holder: Holder, waited seconds: Int, at now: Date) -> Decision {
        let transitions = settle(at: now)
        queue.removeAll { $0.holder.key == holder.key && now >= $0.until }
        guard let term else {
            let taken = take(by: holder, at: now)
            return Decision(answer: taken.answer, transitions: transitions + taken.transitions)
        }
        guard term.holder.key == holder.key else {
            return Decision(answer: .failure(.waitedOut(seconds: seconds, term)), transitions: transitions)
        }
        return Decision(answer: .success(term), transitions: transitions)
    }

    /// `control release` from `holder` at `now`: the holder's lease ends
    /// (`released`) and the first waiter gets it; from anyone else it
    /// changes nothing.
    public mutating func release(by holder: Holder, at now: Date) -> [Transition] {
        let transitions = settle(at: now)
        guard let term, term.holder.key == holder.key else { return transitions }
        self.term = nil
        return transitions + [.ended(term.holder, .released)] + settle(at: now)
    }

    /// The person's Stop at `now`: the lease ends (`stopped`), its holder is
    /// barred for `bar`, and the first waiter gets the lease as on a
    /// release. While the lease is free it changes nothing. The holder is
    /// never in the line (its own `take` renews, never queues), so there's
    /// no place there to drop.
    public mutating func stop(at now: Date) -> [Transition] {
        let transitions = settle(at: now)
        guard let term else { return transitions }
        self.term = nil
        bars.removeAll { $0.key == term.holder.key }
        bars.append(Bar(key: term.holder.key, until: now.addingTimeInterval(Self.bar)))
        return transitions + [.ended(term.holder, .stopped)] + settle(at: now)
    }

    /// When the lease held at `now` ends: the time for the app to settle
    /// at, so the banner goes and the next waiter gets the lease with no
    /// request. Nil while it's free.
    public func nextEnd(after now: Date) -> Date? {
        current(at: now)?.ends
    }

    /// Whether `holder` is barred: settled first, so a bar listed is in force.
    private func isBarred(_ holder: Holder) -> Bool {
        bars.contains { $0.key == holder.key }
    }

    /// The lease as `app status` and `state` report it at `now`, or nil
    /// when it's free.
    public func status(at now: Date) -> LeaseStatus? {
        current(at: now).map {
            LeaseStatus(
                holder: $0.holder.name, place: $0.holder.place, secondsLeft: $0.secondsLeft(at: now), waiting: waiting(at: now)
            )
        }
    }
}

/// A term as it goes in the quit's reply and the relaunch's environment: its
/// times as seconds since 1970, whatever the coder's date strategy.
extension ControlLease.Term: Codable {
    private enum CodingKeys: String, CodingKey {
        case holder, taken, ends
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        holder = try container.decode(Holder.self, forKey: .holder)
        taken = Date(timeIntervalSince1970: try container.decode(Double.self, forKey: .taken))
        ends = Date(timeIntervalSince1970: try container.decode(Double.self, forKey: .ends))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(holder, forKey: .holder)
        try container.encode(taken.timeIntervalSince1970, forKey: .taken)
        try container.encode(ends.timeIntervalSince1970, forKey: .ends)
    }
}
