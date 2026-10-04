import Foundation

/// One agent listening for batches: the holder of its `wait`. Its key tells
/// one listener session from the next.
public struct ListenerSession: Codable, Equatable, Sendable {
    public var key: String
    /// The agent's name as people read it: `Claude Code`.
    public var name: String
    /// Where it runs: a Herdr pane, else its working folder.
    public var place: String

    public init(key: String, name: String, place: String) {
        self.key = key
        self.name = name
        self.place = place
    }
}

/// Whether an agent is there for the person's batches.
public enum Presence: String, Codable, Sendable, CaseIterable {
    /// A `wait` is open and the listener has no batch to work on.
    case listening
    /// The listener took a batch that isn't finished, and is alive.
    case working
    /// Nobody waits: a batch sent now waits for the next `wait`.
    case absent
}

/// The listener's side of the app as a pure value, given the time on each
/// call, like the lease: the line of sent batches waiting for a `wait`
/// (`pending`), the batches a listener took and hasn't finished (`taken`),
/// who the listener is (`session`), and whether it's there (`presence`).
///
/// A batch goes `enqueue → deliverNext → finished`. A `wait` from another
/// holder key is a new listener session: what the last one took and didn't
/// finish goes back to the front of the line. `pending`, `taken` and
/// `session` are what's kept on disk; whether a `wait` is open and when the
/// listener was last heard belong to one run of the app.
public struct Outbox: Codable, Equatable, Sendable {
    /// Sent and not yet delivered, first in, first out.
    public private(set) var pending: [BatchRef] = []
    /// Delivered and not finished.
    public private(set) var taken: [BatchRef] = []
    /// The listener of the last `wait`; nil until the first one.
    public private(set) var session: ListenerSession?
    /// Whether a `wait` is open now.
    public private(set) var isWaitOpen = false
    /// When the listener last sent a command or closed its `wait`.
    public private(set) var lastHeard: Date?

    /// How long a listener with a taken batch counts as alive after its
    /// last command: it works between two commands.
    public static let workingGrace: TimeInterval = 120
    /// How long a listener with nothing taken counts as alive after its
    /// `wait` closed: a listener that runs `wait` in a loop doesn't flicker.
    public static let listeningGrace: TimeInterval = 5

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case pending, taken, session
    }

    /// A batch the person sent joins the end of the line.
    public mutating func enqueue(_ ref: BatchRef) {
        guard !pending.contains(ref), !taken.contains(ref) else { return }
        pending.append(ref)
    }

    /// A `wait` opened. From another key than the last one it's a new
    /// listener session: every taken batch goes back to the front of the
    /// line, in the order it was taken. Returns those batches, whose
    /// unfinished comments the caller returns to `sent`.
    @discardableResult
    public mutating func waitOpened(by listener: ListenerSession, at now: Date) -> [BatchRef] {
        var requeued: [BatchRef] = []
        if let session, session.key != listener.key {
            requeued = taken
            pending.insert(contentsOf: taken, at: 0)
            taken = []
        }
        session = listener
        isWaitOpen = true
        lastHeard = now
        return requeued
    }

    /// The open `wait` closed with no batch: its time ran out, its client
    /// went away, or a newer `wait` replaced it and closed in turn.
    public mutating func waitClosed(at now: Date) {
        guard isWaitOpen else { return }
        isWaitOpen = false
        lastHeard = now
    }

    /// The batch the open `wait` gets: the first in line, which is taken
    /// from now on. The `wait` is answered, so it's no longer open. Nil
    /// while no `wait` is open or nothing is in line.
    public mutating func deliverNext(at now: Date) -> BatchRef? {
        guard isWaitOpen, !pending.isEmpty else { return nil }
        let ref = pending.removeFirst()
        taken.append(ref)
        isWaitOpen = false
        lastHeard = now
        return ref
    }

    /// The reply that carried `ref` couldn't be written: the listener never
    /// got it, so it's first in line again.
    public mutating func undelivered(_ ref: BatchRef) {
        guard let index = taken.firstIndex(of: ref) else { return }
        taken.remove(at: index)
        pending.insert(ref, at: 0)
    }

    /// `ref` leaves the line undelivered: there's nothing of it to deliver.
    public mutating func discard(_ ref: BatchRef) {
        pending.removeAll { $0 == ref }
    }

    /// The listener has nothing left to do on `ref`.
    public mutating func finished(_ ref: BatchRef) {
        taken.removeAll { $0 == ref }
    }

    /// The listener sent a command: it's alive.
    public mutating func heard(at now: Date) {
        lastHeard = now
    }

    /// Whether an agent is there at `now`. `working` while the listener has
    /// a taken batch and is alive; `listening` while it's alive with
    /// nothing taken; `absent` otherwise. Alive is an open `wait`, or a
    /// last word less than `workingGrace` ago with a batch taken and less
    /// than `listeningGrace` ago without.
    public func presence(at now: Date) -> Presence {
        let grace = taken.isEmpty ? Self.listeningGrace : Self.workingGrace
        let alive = isWaitOpen || lastHeard.map { now.timeIntervalSince($0) < grace } ?? false
        guard alive else { return .absent }
        return taken.isEmpty ? .listening : .working
    }
}
