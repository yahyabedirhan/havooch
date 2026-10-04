import Foundation

/// Which batch goes to whom. It keeps the one listener session and every
/// batch that isn't finished, each `pending` (no listener has it) or
/// `taken`. A value given the time on each call, as the lease is.
public struct ListenerLedger: Codable, Equatable, Sendable {
    /// One listener, named by its holder key: one agent session.
    public struct Session: Codable, Equatable, Sendable {
        public var key: String
        public var name: String
        public var place: String
        public var firstSeen: Date
        /// When its last listener command came.
        public var lastSeen: Date
        /// Per video (its content hash), the context text it last got.
        public var contextSent: [String: String]
    }

    /// One batch on its way to the listener.
    public struct Delivery: Codable, Equatable, Sendable {
        public var batch: BatchID
        /// The content hash of the batch's video.
        public var video: String
        public var sentAt: Date
        /// The key of the session that has it; nil while it's pending.
        public var takenBy: String?
        public var takenAt: Date?

        public var isPending: Bool { takenBy == nil }
    }

    /// Where a batch stands on its way, as `state` names it.
    public enum Standing: String, Codable, Sendable {
        case pending, taken, finished
    }

    /// How long after its last command a session that has a batch still
    /// counts as working on it, with no `wait` open.
    public static let workingWindow: TimeInterval = 120

    public private(set) var session: Session?
    /// Oldest first. A finished one is removed.
    public private(set) var deliveries: [Delivery]

    public init() {
        session = nil
        deliveries = []
    }

    /// A batch was sent: it waits for a listener.
    public mutating func enqueue(_ batch: BatchID, video: String, sentAt: Date) {
        guard !deliveries.contains(where: { $0.batch == batch }) else { return }
        deliveries.append(Delivery(batch: batch, video: video, sentAt: sentAt))
    }

    /// A listener command arrived from `holder`. The session's own key
    /// only notes the time. Another key starts a new session: the one
    /// before is over, and the batches it took and didn't finish are
    /// pending again. Those are returned, as they now stand.
    @discardableResult
    public mutating func attach(_ holder: (key: String, name: String, place: String), now: Date) -> [Delivery] {
        if session?.key == holder.key {
            session?.name = holder.name
            session?.place = holder.place
            session?.lastSeen = now
            return []
        }
        session = Session(key: holder.key, name: holder.name, place: holder.place, firstSeen: now, lastSeen: now, contextSent: [:])
        var requeued: [Delivery] = []
        for index in deliveries.indices where !deliveries[index].isPending {
            deliveries[index].takenBy = nil
            deliveries[index].takenAt = nil
            requeued.append(deliveries[index])
        }
        return requeued
    }

    /// The oldest pending delivery, leaving out the batches in `except`:
    /// those whose reply is being written to a listener right now.
    public func next(except: Set<BatchID> = []) -> Delivery? {
        deliveries.first { $0.isPending && !except.contains($0.batch) }
    }

    /// What of the context `text` of the video `video` goes with the next
    /// batch to the session: the text when the session got none for that
    /// video yet, or another one; nil when it has this very text, when the
    /// text is empty, or when there is no session.
    public func contextToSend(_ text: String, video: String) -> String? {
        guard let session, !text.isEmpty, session.contextSent[video] != text else { return nil }
        return text
    }

    /// The reply carrying `batch` reached the listener `key`: the batch is
    /// taken, and the `context` that went with it is remembered for its
    /// video. A listener that is no longer the session (another one
    /// started while the reply was written) takes nothing: the batch stays
    /// pending for the session there is.
    public mutating func delivered(_ batch: BatchID, to key: String, context: String?, now: Date) {
        guard session?.key == key, let index = deliveries.firstIndex(where: { $0.batch == batch }) else { return }
        deliveries[index].takenBy = key
        deliveries[index].takenAt = now
        session?.lastSeen = now
        if let context { session?.contextSent[deliveries[index].video] = context }
    }

    /// Every comment of `batch` is done or failed: nothing is left to deliver.
    public mutating func finish(_ batch: BatchID) {
        deliveries.removeAll { $0.batch == batch }
    }

    /// Brings the ledger in line with `reviews`, every review there is, as
    /// both were read at launch. The reviews say which batches exist and
    /// the ledger only who has them. So when the app ended between the two
    /// writes of one action, or the ledger's file was lost, no batch is:
    /// an unfinished batch that isn't here is pending, and a delivery
    /// whose batch is finished, or is in no review, is gone.
    public mutating func reconcile(with reviews: [Review]) {
        let known = Dictionary(reviews.map { ($0.video.contentHash, $0) }) { first, _ in first }
        deliveries.removeAll { delivery in
            guard let review = known[delivery.video], (try? review.batch(delivery.batch)) != nil else { return true }
            return review.isFinished(delivery.batch)
        }
        let kept = deliveries.count
        for review in reviews {
            for batch in review.batches where !review.isFinished(batch.id) {
                enqueue(batch.id, video: review.video.contentHash, sentAt: batch.sentAt)
            }
        }
        // Oldest first, as `enqueue` alone keeps them.
        if deliveries.count != kept {
            deliveries = deliveries.enumerated()
                .sorted { ($0.element.sentAt, $0.offset) < ($1.element.sentAt, $1.offset) }
                .map(\.element)
        }
    }

    /// Where `batch` stands: a batch that isn't here any more is finished.
    public func standing(of batch: BatchID) -> Standing {
        guard let delivery = deliveries.first(where: { $0.batch == batch }) else { return .finished }
        return delivery.isPending ? .pending : .taken
    }

    /// Whether the session has a batch it took and didn't finish.
    public var hasTaken: Bool {
        guard let session else { return false }
        return deliveries.contains { $0.takenBy == session.key }
    }

    /// Whether a listener is there, at `now`:
    ///
    ///     a wait is open, nothing taken              listening
    ///     a wait is open, a batch taken              working
    ///     no wait, a batch taken, a command under
    ///     `workingWindow` ago                        working
    ///     otherwise                                  absent
    public func presence(waitOpen: Bool, now: Date) -> Presence {
        if waitOpen { return hasTaken ? .working : .listening }
        guard let session, hasTaken, now.timeIntervalSince(session.lastSeen) < Self.workingWindow else { return .absent }
        return .working
    }
}
