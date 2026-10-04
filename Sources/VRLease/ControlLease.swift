import Foundation

/// The lease on app control: which agent may send operator commands, and
/// until when. A pure value, given the time on each call.
///
/// This is the seam only. It records who used the app last and for how long
/// that use counts, and it grants every request: a command from another
/// holder takes the lease over. The rules that refuse one (a lease in use,
/// the line of waiters, the person's Stop and its bar) come with `control
/// take` and `control release`, and change nothing for the callers here.
public struct ControlLease: Equatable, Sendable {
    /// How long after its holder's last command the lease ends.
    public static let renewal: TimeInterval = 60
    /// How long after it was taken the lease ends at most.
    public static let cap: TimeInterval = 5 * 60
    /// The variable a relaunch hands the lease over in (`handover`).
    public static let handoverVariable = "VIDEO_REVIEW_CONTROL_LEASE"

    /// One holder's lease: who, since when, until when.
    public struct Term: Codable, Equatable, Sendable {
        public var holder: Holder
        public var taken: Date
        public var ends: Date

        public init(holder: Holder, taken: Date, ends: Date) {
            self.holder = holder
            self.taken = taken
            self.ends = ends
        }
    }

    /// Why a request doesn't get the lease.
    public enum Refusal: Error, Equatable, Sendable {
        /// Another holder has it.
        case inUse(Term)

        /// One line for the reply's `error`: the holder, its place and the
        /// lease's end as `HH:mm:ss`.
        public func message(at now: Date, timeZone: TimeZone) -> String {
            switch self {
            case .inUse(let term):
                let format = Date.FormatStyle(timeZone: timeZone).hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).second(.twoDigits)
                let left = max(0, Int(term.ends.timeIntervalSince(now).rounded(.up)))
                return "video-review is in use by \(term.holder.name) in \(term.holder.place) until \(term.ends.formatted(format)) "
                    + "(\(left)s left); `video-review control take --wait <seconds>` to queue"
            }
        }
    }

    /// The answer to a request for the lease.
    public struct Decision: Equatable, Sendable {
        public var answer: Result<Term, Refusal>
    }

    /// The lease as `state` and `app status` report it.
    public struct Status: Codable, Equatable, Sendable {
        /// The holder's name (`Claude Code`).
        public var holder: String
        /// Where the holder runs: `Herdr pane <id>`, or its working folder.
        public var place: String
        public var secondsLeft: Int
        public var waiting: Int
    }

    private var term: Term?

    /// A free lease.
    public init() {}

    /// The lease a relaunched app starts with: the one `handover` put in
    /// `environment`, when it hasn't ended by `now`; free otherwise.
    public init(environment: [String: String], at now: Date) {
        guard let text = environment[Self.handoverVariable],
              let term = try? JSONDecoder().decode(Term.self, from: Data(text.utf8)),
              term.ends > now
        else { return }
        self.term = term
    }

    /// The variable that hands `term` over to the app a relaunch starts, so
    /// `app open --demo` keeps its opener's lease across the quit.
    public static func handover(_ term: Term) -> [String: String] {
        let encoder = JSONEncoder()
        // Sorted keys give one text for one term, whatever the run.
        encoder.outputFormatting = .sortedKeys
        // A struct of strings and dates always encodes.
        return [handoverVariable: String(decoding: try! encoder.encode(term), as: UTF8.self)]
    }

    /// The lease in force at `now`, or nil when it's free.
    public func current(at now: Date) -> Term? {
        guard let term, term.ends > now else { return nil }
        return term
    }

    public func status(at now: Date) -> Status? {
        guard let term = current(at: now) else { return nil }
        return Status(
            holder: term.holder.name, place: term.holder.place,
            secondsLeft: max(0, Int(term.ends.timeIntervalSince(now).rounded(.up))), waiting: 0
        )
    }

    /// An operator command from `holder` at `now`: its holder's lease is
    /// renewed, never past the cap; anyone else starts a new one.
    public mutating func use(by holder: Holder, at now: Date) -> Decision {
        var next = Term(holder: holder, taken: now, ends: now.addingTimeInterval(Self.renewal))
        if let term = current(at: now), term.holder.key == holder.key {
            next.taken = term.taken
            next.ends = min(now.addingTimeInterval(Self.renewal), term.taken.addingTimeInterval(Self.cap))
        }
        term = next
        return Decision(answer: .success(next))
    }
}
