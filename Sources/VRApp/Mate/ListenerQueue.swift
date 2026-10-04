import Foundation
import Observation
import VRLease
import VRReview

/// The listener's side of the app: the open `wait`s and the ledger of
/// deliveries. A batch goes to the oldest open `wait`, or waits for the
/// next one. It counts as taken only once its reply reached the listener
/// (`delivered`); a reply that couldn't be written leaves it pending
/// (`undelivered`). One listener session at a time.
@MainActor @Observable
final class ListenerQueue {
    /// A batch handed to a `wait`, until its reply is written or not.
    struct Handed: Equatable, Sendable {
        var batch: BatchID
        /// The key of the listener session it was handed to.
        var listener: String
        /// The context that went with it, for the session to be remembered by.
        var context: String?
    }

    /// How a `wait` ends.
    enum WaitOutcome: Equatable, Sendable {
        /// The next batch, as the payload's one line of JSON.
        case batch(Handed, payload: String)
        /// Its `--timeout` ran out with no batch.
        case timedOut
        case refused(String)
        /// Its connection closed: nobody reads the answer.
        case gone
    }

    /// One open `wait`: who listens, and how it gets its answer.
    private struct Waiter {
        var ticket: UUID
        var holder: Holder
        var answer: CheckedContinuation<WaitOutcome, Never>
        /// Ends the wait when its `--timeout` runs out; cancelled once it's answered.
        var timeout: Task<Void, Never>?
    }

    /// The listener session and the batches on their way. Kept in memory
    /// for this run.
    private(set) var ledger = ListenerLedger()
    /// The open `wait`s, oldest first.
    private var waiters: [Waiter] = []
    /// The batches whose reply is being written: handed to a `wait`, not
    /// yet taken, and so not handed to a second one.
    private var inFlight: Set<BatchID> = []
    /// Set once the app quits: a `wait` that comes then is refused.
    private var closed = false
    @ObservationIgnored private let desk: ReviewDesk
    @ObservationIgnored private let now: @MainActor () -> Date

    static let quittingRefusal = "video-review is quitting"

    init(desk: ReviewDesk, now: @escaping @MainActor () -> Date) {
        self.desk = desk
        self.now = now
    }

    // MARK: - What the window and `state` show

    /// The listener there is, or was last.
    var session: ListenerLedger.Session? { ledger.session }

    /// Whether a listener is there at `time`.
    func presence(at time: Date) -> Presence {
        ledger.presence(waitOpen: !waiters.isEmpty, now: time)
    }

    /// Whether a listener is there now.
    var presence: Presence { presence(at: now()) }

    /// Whether presence can change by time alone: a listener with a batch
    /// and no `wait` open is `working` only for a while after its last command.
    var presenceRunsOut: Bool { waiters.isEmpty && ledger.hasTaken }

    /// Where `batch` stands on its way to the listener.
    func standing(of batch: BatchID) -> ListenerLedger.Standing {
        ledger.standing(of: batch)
    }

    // MARK: - Sending

    /// `batch` of `video` was sent: it goes to the oldest open `wait`, or
    /// waits for the next one.
    func enqueue(_ batch: Batch, video: VideoInfo) {
        ledger.enqueue(batch.id, video: video.contentHash, sentAt: batch.sentAt)
        deliverIfPossible()
    }

    // MARK: - Listening

    /// `wait`: answered with the next batch, at once when one is pending.
    /// The caller stays suspended meanwhile, and the main actor free. A
    /// `wait` from another listener while one is open is refused. A new
    /// listener (another key than the session's) starts a new session, and
    /// the batches the one before took and didn't finish go out again.
    /// When the caller's task is cancelled (its connection closed), the
    /// wait ends with nothing handed over.
    func wait(holder: Holder, timeout: Int?) async -> WaitOutcome {
        guard !closed else { return .refused(Self.quittingRefusal) }
        if let open = waiters.first(where: { $0.holder.key != holder.key }) {
            return .refused("\(open.holder.name) in \(open.holder.place) is already listening; one listener at a time")
        }
        for delivery in ledger.attach((key: holder.key, name: holder.name, place: holder.place), now: now()) {
            // A review this run doesn't have has nothing to put back.
            _ = try? desk.change(delivery.video) { review in review.requeue(delivery.batch) }
        }
        let ticket = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let running = timeout.map { seconds in
                    Task { [weak self] in
                        do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
                        self?.end(ticket, with: .timedOut)
                    }
                }
                waiters.append(Waiter(ticket: ticket, holder: holder, answer: continuation, timeout: running))
                deliverIfPossible()
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.end(ticket, with: .gone) }
        }
    }

    /// Ends the open `wait` `ticket` with `outcome`, unless it was
    /// answered already.
    private func end(_ ticket: UUID, with outcome: WaitOutcome) {
        guard let index = waiters.firstIndex(where: { $0.ticket == ticket }) else { return }
        let waiter = waiters.remove(at: index)
        waiter.timeout?.cancel()
        waiter.answer.resume(returning: outcome)
    }

    /// The one step `enqueue` and `wait` both end in: while a batch is
    /// pending and a `wait` is open, the oldest `wait` gets the oldest batch.
    private func deliverIfPossible() {
        while let waiter = waiters.first, let delivery = ledger.next(except: inFlight) {
            guard let review = desk.review(delivery.video), let batch = try? review.batch(delivery.batch),
                  !review.isFinished(batch.id)
            else {
                // Nothing of it is left to deliver.
                ledger.finish(delivery.batch)
                continue
            }
            // Read now, not at the send: what goes out depends on who
            // gets it. The session remembers what it got in `delivered`.
            let hash = review.video.contentHash
            let context = ledger.contextToSend(ContextSource.text(for: review), video: hash)
            let payload = BatchPayload.make(
                batch: batch, review: review, context: context,
                keyframe: { [layout = desk.layout] in layout.keyframe($0, of: hash).path },
                crop: { [layout = desk.layout] in layout.crop($0, of: hash).path }
            )
            inFlight.insert(batch.id)
            end(waiter.ticket, with: .batch(
                Handed(batch: batch.id, listener: waiter.holder.key, context: context),
                payload: String(decoding: payload.encoded(), as: UTF8.self) + "\n"
            ))
        }
    }

    /// The reply carrying `handed` was written to its listener: the batch
    /// is taken.
    func delivered(_ handed: Handed) {
        inFlight.remove(handed.batch)
        ledger.delivered(handed.batch, to: handed.listener, context: handed.context, now: now())
        // Left pending when its listener is no longer the session: the next `wait` gets it.
        deliverIfPossible()
    }

    /// The reply carrying `handed` couldn't be written (its listener had
    /// gone): the batch is still pending, for the next `wait`.
    func undelivered(_ handed: Handed) {
        inFlight.remove(handed.batch)
        deliverIfPossible()
    }

    /// The app quits: every open `wait` hears why, instead of a dropped
    /// connection, and a later one is refused.
    func quitting() {
        closed = true
        for waiter in waiters { end(waiter.ticket, with: .refused(Self.quittingRefusal)) }
    }
}
