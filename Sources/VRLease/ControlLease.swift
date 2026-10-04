import Foundation

/// App control's lease: who may send operator commands, and until when.
///
/// This is the pass-through the first build ships: every holder is let
/// through and nothing is held, so `current` and `status` report a free
/// lease. The lease ticket replaces the bodies with the real rules (take,
/// renew, expire, cap, queue, stop, bar) behind these same calls; the
/// control server already asks `use(by:at:)` before every operator command.
public struct ControlLease: Equatable, Sendable {
    /// How long one operator command holds the lease for.
    public static let renewal: TimeInterval = 60

    /// One holding of the lease: by whom, since when, and when it ends.
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

    /// Why a holder may not act.
    public enum Refusal: Error, Equatable, Sendable {
        /// Another holder has the lease.
        case inUse(Term)

        /// One line for the reply's `error`.
        public var message: String {
            switch self {
            case .inUse(let term):
                return "video-review is in use by \(term.holder.name) in \(term.holder.place)"
            }
        }
    }

    /// The lease's answer to one call.
    public struct Decision: Equatable, Sendable {
        public var answer: Result<Term, Refusal>

        public init(answer: Result<Term, Refusal>) {
            self.answer = answer
        }
    }

    public init() {}

    /// An operator command by `holder` at `now`: the term it acts under, or
    /// why it may not.
    public mutating func use(by holder: Holder, at now: Date) -> Decision {
        Decision(answer: .success(Term(holder: holder, taken: now, ends: now.addingTimeInterval(Self.renewal))))
    }

    /// The term that holds at `now`, or nil when the lease is free.
    public func current(at now: Date) -> Term? {
        nil
    }

    /// The lease as `app status` and `state` report it, or nil when free.
    public func status(at now: Date) -> LeaseStatus? {
        nil
    }
}
