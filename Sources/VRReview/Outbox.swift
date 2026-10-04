import Foundation

/// The batches that were sent and aren't finished, and the listener they go
/// to: which batch a `wait` gets, what goes back in the queue when another
/// listener session arrives, whether a listener is there, and which video's
/// context this listener already has. A pure value: the time is given on
/// each call.
public struct Outbox: Equatable, Sendable {
    /// One sent batch on its way to a listener.
    public struct Parcel: Codable, Equatable, Sendable {
        public var batchID: String
        public var videoHash: String
        public var delivery: Delivery

        public init(batchID: String, videoHash: String, delivery: Delivery) {
            self.batchID = batchID
            self.videoHash = videoHash
            self.delivery = delivery
        }
    }

    public enum Delivery: Codable, Equatable, Sendable {
        /// Waiting for a `wait`.
        case pending
        /// Given to the listener session `by` (its holder key).
        case taken(by: String, at: Date)
    }

    /// What the person sees of the listener.
    public enum Presence: String, Codable, Equatable, Sendable {
        /// No `wait` is open, and none delivered a batch a moment ago.
        case absent
        /// A listener waits and has no batch in work.
        case listening
        /// A listener is there and has a batch it didn't finish.
        case working
    }

    /// The listener session: the holder its `wait`s come from.
    public struct Listener: Equatable, Sendable {
        public var key: String
        public var name: String

        public init(key: String, name: String) {
            self.key = key
            self.name = name
        }
    }

    /// How long after a delivered batch the listener still counts as there,
    /// in seconds: it reads the batch, then starts `wait` again.
    public static let grace: TimeInterval = 30

    /// The batches not finished, oldest first.
    public private(set) var parcels: [Parcel]
    /// The last listener session a `wait` came from.
    public private(set) var listener: Listener?
    /// How many of the listener's `wait`s are open.
    private var waits = 0
    /// When a `wait` last closed with a batch delivered.
    private var delivered: Date?
    /// The context text this listener session already got, by video hash.
    private var contexts: [String: String] = [:]

    public init(parcels: [Parcel] = []) {
        self.parcels = parcels
    }

    public func parcel(_ batchID: String) -> Parcel? {
        parcels.first { $0.batchID == batchID }
    }

    /// A batch was sent: it waits for a `wait`.
    public mutating func post(batchID: String, videoHash: String) {
        parcels.append(Parcel(batchID: batchID, videoHash: videoHash, delivery: .pending))
    }

    /// A `wait` opened. From another session than the last listener's, it's
    /// a listener that started again: every batch another session took and
    /// didn't finish is pending again, and nothing counts as already sent to
    /// it. Returns the parcels put back, so their comments go back to `sent`.
    @discardableResult
    public mutating func arrive(key: String, name: String, at now: Date) -> [Parcel] {
        var requeued: [Parcel] = []
        if listener?.key != key {
            for index in parcels.indices {
                if case .taken(let by, _) = parcels[index].delivery, by != key {
                    parcels[index].delivery = .pending
                    requeued.append(parcels[index])
                }
            }
            contexts = [:]
            waits = 0
            delivered = nil
        }
        listener = Listener(key: key, name: name)
        waits += 1
        return requeued
    }

    /// The oldest pending batch, taken by the listener; nil when there's
    /// none, or no listener.
    public mutating func take(at now: Date) -> Parcel? {
        guard let listener, let index = parcels.firstIndex(where: { $0.delivery == .pending }) else { return nil }
        parcels[index].delivery = .taken(by: listener.key, at: now)
        return parcels[index]
    }

    /// The batch's payload couldn't be written to its `wait` (the client is
    /// gone): it's pending again, and its video's context counts as not sent.
    public mutating func undelivered(_ batchID: String) {
        guard let index = parcels.firstIndex(where: { $0.batchID == batchID }) else { return }
        parcels[index].delivery = .pending
        contexts[parcels[index].videoHash] = nil
    }

    /// A `wait` of the session `key` closed, with a batch delivered or not.
    /// One of a session that isn't the listener any more changes nothing.
    public mutating func leave(key: String, at now: Date, delivered: Bool) {
        guard listener?.key == key else { return }
        waits = max(0, waits - 1)
        if delivered { self.delivered = now }
    }

    /// Every comment of the batch is done or failed: it leaves the outbox.
    public mutating func finish(_ batchID: String) {
        parcels.removeAll { $0.batchID == batchID }
    }

    /// The context to send with a batch of the video `videoHash`: `text`
    /// the first time this listener session gets it and whenever it changed,
    /// else nil. Nil for no text.
    public mutating func context(for videoHash: String, text: String?) -> String? {
        guard let text, !text.isEmpty, contexts[videoHash] != text else { return nil }
        contexts[videoHash] = text
        return text
    }

    /// Whether a listener is there at `now`, and whether it has work.
    public func presence(at now: Date) -> Presence {
        guard let listener else { return .absent }
        let justDelivered = delivered.map { now.timeIntervalSince($0) < Self.grace } ?? false
        guard waits > 0 || justDelivered else { return .absent }
        let hasWork = parcels.contains {
            if case .taken(let by, _) = $0.delivery { by == listener.key } else { false }
        }
        return hasWork ? .working : .listening
    }
}
