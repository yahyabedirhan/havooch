import Foundation

/// One agent listening for sends: the holder of its `wait`. Its key tells
/// one listener session from the next.
public struct ListenerSession: Codable, Equatable, Sendable {
    public var key: String
    /// The agent's name as people read it: `Claude Code`.
    public var name: String
    /// Where it runs: a Herdr pane, else its working folder.
    public var place: String
    /// When its first `wait` opened: the listener card's "Since". Nil for
    /// a session kept by a build before it.
    public var since: Date?

    public init(key: String, name: String, place: String, since: Date? = nil) {
        self.key = key
        self.name = name
        self.place = place
        self.since = since
    }
}

/// Whether an agent is there for the person's sends.
public enum Presence: String, Codable, Sendable, CaseIterable {
    /// A `wait` is open and the listener has no send to work on.
    case listening
    /// The listener took a send that isn't finished, and is alive.
    case working
    /// Nobody waits: a send made now waits for the next `wait`.
    case absent
}

/// The listener's side of the app as a pure value, given the time on each
/// call, like the lease: the line of sends waiting for a `wait`
/// (`pending`), the sends a listener took and hasn't finished (`taken`),
/// who the listener is (`session`), and whether it's there (`presence`).
///
/// A send goes `enqueue → handOut → written → finished`: it's handed to
/// the open `wait` and stays in line, in flight, until the reply that
/// carries it is written; only then is it taken. A reply that can't be
/// written leaves it first in line. A `wait` from another
/// holder key is a new listener session: what the last one took and didn't
/// finish goes back to the front of the line, and it gets each video's
/// context again (`contextSent`). `pending`, `taken`, `session` and
/// `contextSent` are what's kept on disk; whether a `wait` is open, what's
/// in flight and when the listener was last heard belong to one run of the
/// app.
public struct Outbox: Codable, Equatable, Sendable {
    /// Sent and not yet delivered, first in, first out.
    public private(set) var pending: [SendRef] = []
    /// Delivered and not finished.
    public private(set) var taken: [SendRef] = []
    /// The sends handed to a `wait` whose reply is being written, each with
    /// the key of the listener session it went to. They stay in `pending`
    /// and no other `wait` gets them.
    public private(set) var inFlight: [SendRef: String] = [:]
    /// The listener of the last `wait`; nil until the first one.
    public private(set) var session: ListenerSession?
    /// Whether a `wait` is open now.
    public private(set) var isWaitOpen = false
    /// How many `ask`s are open now: the listener waits for an answer.
    public private(set) var openAsks = 0
    /// When the listener last sent a command or closed its `wait`.
    public private(set) var lastHeard: Date?
    /// The context this listener session has, by its review's
    /// `contextKey` (a plain video's content hash, or `project-<slug>`):
    /// the digest of the text it last got. Empty for a new session.
    public private(set) var contextSent: [String: String] = [:]

    /// How long a listener with a taken send counts as alive after its
    /// last command: it works between two commands.
    public static let workingGrace: TimeInterval = 120
    /// How long a listener with nothing taken counts as alive after its
    /// `wait` closed: a listener that runs `wait` in a loop doesn't flicker.
    public static let listeningGrace: TimeInterval = 5

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case pending, taken, session, contextSent
    }

    /// Reads an outbox as it's kept on disk. No `wait` is open and nothing
    /// was heard yet: those belong to the run that wrote it. A key that's
    /// missing reads as empty.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pending = try container.decodeIfPresent([SendRef].self, forKey: .pending) ?? []
        taken = try container.decodeIfPresent([SendRef].self, forKey: .taken) ?? []
        session = try container.decodeIfPresent(ListenerSession.self, forKey: .session)
        contextSent = try container.decodeIfPresent([String: String].self, forKey: .contextSent) ?? [:]
    }

    /// Makes the outbox agree with the reviews at launch. `unfinished` is
    /// every send on disk with a message the listener hasn't finished, in
    /// the order sent. A send that's no longer one of them leaves
    /// `pending` and `taken`; one that's in neither joins the end of the
    /// line. So a run that ended between saving a review and saving the
    /// outbox, or an outbox file that was lost, costs no feedback.
    public mutating func reconcile(unfinished: [SendRef]) {
        let known = Set(unfinished)
        pending.removeAll { !known.contains($0) }
        taken.removeAll { !known.contains($0) }
        var present = Set(pending).union(taken)
        for ref in unfinished where present.insert(ref).inserted { pending.append(ref) }
    }

    /// The part of this outbox that is the review `key`'s: its sends in
    /// line and taken, and the context its listener had of its videos,
    /// with the same listener session. The outbox of builds before a
    /// listener per review held every video's sends, and splits this way.
    public func part(for key: ReviewKey) -> Outbox {
        var part = Outbox()
        part.pending = pending.filter(key.holds)
        part.taken = taken.filter(key.holds)
        part.session = session
        part.contextSent = contextSent.filter { key.covers($0.key) }
        return part
    }

    /// This outbox as the review `to`'s, after the review `from` became it
    /// (`project new` moves a plain video's review into a project): its
    /// sends name the new review, and the listener session stays, so the
    /// listener keeps listening. The context it had of `from` is kept
    /// under `to`.
    public func rekeyed(from: ReviewKey, to: ReviewKey) -> Outbox {
        var moved = self
        let rename = { (ref: SendRef) in ref.review == from ? SendRef(sendID: ref.sendID, review: to) : ref }
        moved.pending = pending.map(rename)
        moved.taken = taken.map(rename)
        moved.inFlight = Dictionary(inFlight.map { (rename($0.key), $0.value) }, uniquingKeysWith: { first, _ in first })
        if let context = contextSent[from.contextKey] {
            moved.contextSent[from.contextKey] = nil
            moved.contextSent[to.contextKey] = context
        }
        return moved
    }

    /// Whether `other` is the same on disk: the same line, taken sends,
    /// session and context sent.
    public func isKeptAs(_ other: Outbox) -> Bool {
        pending == other.pending && taken == other.taken && session == other.session && contextSent == other.contextSent
    }

    /// A send the person made joins the end of the line.
    public mutating func enqueue(_ ref: SendRef) {
        guard !pending.contains(ref), !taken.contains(ref) else { return }
        pending.append(ref)
    }

    /// A `wait` opened. From another key than the last one it's a new
    /// listener session: every taken send goes back to the front of the
    /// line, in the order it was taken. Returns those sends, whose
    /// unfinished messages the caller returns to `sent`.
    @discardableResult
    public mutating func waitOpened(by listener: ListenerSession, at now: Date) -> [SendRef] {
        var requeued: [SendRef] = []
        if let session, session.key != listener.key {
            requeued = taken
            pending.insert(contentsOf: taken, at: 0)
            taken = []
            // The new session has read no video's context yet.
            contextSent = [:]
        }
        var listener = listener
        // The same session keeps the time it started; a new one starts now.
        listener.since = (session?.key == listener.key ? session?.since : nil) ?? listener.since ?? now
        session = listener
        isWaitOpen = true
        lastHeard = now
        return requeued
    }

    /// The person let the listener go: Disconnect while it listens, or
    /// Forget while it reconnects. Nobody listens from now on, and the next
    /// `wait` starts a new session. What it took and didn't finish goes
    /// back to the front of the line, as for a new session; its context is
    /// forgotten. Returns those sends, whose unfinished messages the caller
    /// returns to `sent`.
    @discardableResult
    public mutating func letGo() -> [SendRef] {
        let requeued = taken
        pending.insert(contentsOf: taken, at: 0)
        taken = []
        contextSent = [:]
        session = nil
        isWaitOpen = false
        lastHeard = nil
        return requeued
    }

    /// The open `wait` closed with no send: its time ran out, its client
    /// went away, or a newer `wait` replaced it and closed in turn.
    public mutating func waitClosed(at now: Date) {
        guard isWaitOpen else { return }
        isWaitOpen = false
        lastHeard = now
    }

    /// The send the open `wait` gets: the first in line that isn't in
    /// flight, which is in flight from now on. The `wait` is answered, so
    /// it's no longer open. Nil while no `wait` is open or nothing is in
    /// line.
    public mutating func handOut(at now: Date) -> SendRef? {
        guard isWaitOpen, let session, let ref = pending.first(where: { inFlight[$0] == nil }) else { return nil }
        inFlight[ref] = session.key
        isWaitOpen = false
        lastHeard = now
        return ref
    }

    /// The reply that carried `ref` was written: the listener has it, so
    /// it's taken. A listener session that ended meanwhile (another key
    /// opened a `wait`) took nothing: the send stays in line for the
    /// session there is.
    public mutating func written(_ ref: SendRef) {
        guard let key = inFlight.removeValue(forKey: ref), key == session?.key,
              let index = pending.firstIndex(of: ref) else { return }
        pending.remove(at: index)
        taken.append(ref)
    }

    /// The reply that carried `ref` couldn't be written: the listener never
    /// got it. It never left the line, so it's first in line again.
    public mutating func undelivered(_ ref: SendRef) {
        inFlight[ref] = nil
        // The context that payload may have carried was lost with it.
        contextSent[ref.review.contextKey] = nil
    }

    /// `ref` leaves the line undelivered: there's nothing of it to deliver.
    public mutating func discard(_ ref: SendRef) {
        pending.removeAll { $0 == ref }
    }

    /// The listener has nothing left to do on `ref`: it leaves the line
    /// and the taken sends.
    public mutating func finished(_ ref: SendRef) {
        taken.removeAll { $0 == ref }
        pending.removeAll { $0 == ref }
        inFlight[ref] = nil
    }

    // MARK: - The video context

    /// The payload's `context` for a send of the review whose
    /// `contextKey` is `key` (a plain video's content hash), whose context
    /// is `text` now: the text when this session hasn't had it (its first
    /// send of the review, or the text changed since), which it has from
    /// now on; nil when the session has this very text, and when there's
    /// no text.
    public mutating func context(for key: String, text: String?) -> String? {
        guard let text, isContextDue(for: key, text: text) else { return nil }
        contextSent[key] = Self.digest(text)
        return text
    }

    /// Whether the next send of the review whose `contextKey` is `key`
    /// carries `text`: there is a text, and it isn't the one this session
    /// last got.
    public func isContextDue(for key: String, text: String?) -> Bool {
        guard let text, !text.isEmpty else { return false }
        return contextSent[key] != Self.digest(text)
    }

    /// A short name for `text` that's the same in every run of the app:
    /// its length and its 64-bit FNV-1a hash. It tells a changed text from
    /// the one a session has; it keeps no secret.
    static func digest(_ text: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        var count = 0
        for byte in text.utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01b3
            count += 1
        }
        return "\(count)-" + String(hash, radix: 16)
    }

    /// The listener sent a command: it's alive.
    public mutating func heard(at now: Date) {
        lastHeard = now
    }

    /// An `ask` is held open for the person's answer: the listener is
    /// there for as long as it waits.
    public mutating func askOpened(at now: Date) {
        openAsks += 1
        lastHeard = now
    }

    /// An open `ask` ended: answered, out of time, or its client gone.
    public mutating func askClosed(at now: Date) {
        guard openAsks > 0 else { return }
        openAsks -= 1
        lastHeard = now
    }

    /// Whether an agent is there at `now`. `working` while the listener has
    /// a taken send and is alive; `listening` while it's alive with
    /// nothing taken; `absent` otherwise. Alive is an open `wait` or
    /// `ask`, or a last word less than `workingGrace` ago with a send
    /// taken and less than `listeningGrace` ago without.
    public func presence(at now: Date) -> Presence {
        let grace = taken.isEmpty ? Self.listeningGrace : Self.workingGrace
        let alive = isWaitOpen || openAsks > 0 || lastHeard.map { now.timeIntervalSince($0) < grace } ?? false
        guard alive else { return .absent }
        return taken.isEmpty ? .listening : .working
    }
}
