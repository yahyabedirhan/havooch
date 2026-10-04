import Foundation
import Observation
import ReviewCore
import ReviewStore
import ReviewWire

/// The listener's side of the app: it holds the `Outbox` (the rules), the
/// one open `wait` (a held connection, like a `take` waiting in line) and
/// assembles the payload at the moment a `wait` takes a batch. The views
/// read the presence from it.
@MainActor
@Observable
final class ListenerQueue {
    /// How a `wait` ends.
    enum Outcome: Equatable {
        /// The next batch, with the JSON the command prints.
        case batch(BatchRef, payload: String)
        /// Its time ran out with no batch.
        case ranOut
        /// A newer `wait` took its place.
        case replaced
        /// Nobody reads the answer: its client went away, or the app quits.
        case gone
    }

    /// The pending and taken batches, the listener session and its presence.
    private(set) var outbox = Outbox()

    /// The `wait` that's held open until a batch is sent.
    private struct OpenWait {
        var ticket = UUID()
        /// The connection it came over, to tell when its client goes away.
        var connection: UUID?
        var answer: CheckedContinuation<Outcome, Never>
        /// Ends the wait when its time runs out; cancelled once it's answered.
        var timeout: Task<Void, Never>?
    }

    @ObservationIgnored private var open: OpenWait?
    @ObservationIgnored private let desk: ReviewDesk
    @ObservationIgnored private let images: ImageFiles
    @ObservationIgnored private let now: @MainActor () -> Date

    init(desk: ReviewDesk, images: ImageFiles, now: @escaping @MainActor () -> Date = { Date() }) {
        self.desk = desk
        self.images = images
        self.now = now
    }

    // MARK: - The person's side

    /// A batch the person sent: the open `wait` gets it at once, else it
    /// waits in line for the next one.
    func enqueue(_ ref: BatchRef) {
        outbox.enqueue(ref)
        deliver()
    }

    /// Whether an agent is there at `time`.
    func presence(at time: Date) -> Presence {
        outbox.presence(at: time)
    }

    /// The listener as `state` reports it at `time`.
    func report(at time: Date) -> StateReport.Listener {
        StateReport.Listener(
            presence: outbox.presence(at: time).rawValue, waitOpen: outbox.isWaitOpen, session: outbox.session?.name,
            pendingBatches: outbox.pending.count, takenBatches: outbox.taken.count
        )
    }

    // MARK: - The listener's side

    /// `video-review wait`: the next batch in line, at once when there is
    /// one, else when the person sends one, for up to `timeout` seconds
    /// (nil: with no limit). A `wait` from another holder than the last is
    /// a new listener session: the batches the last one took and didn't
    /// finish are first in line again, their unfinished comments `sent`. A
    /// `wait` that's still open is replaced: one listener at a time.
    func wait(by holder: Holder, timeout: Int?, connection: UUID? = nil) async -> Outcome {
        let listener = ListenerSession(key: holder.key, name: holder.name, place: holder.place)
        for ref in outbox.waitOpened(by: listener, at: now()) {
            _ = try? desk.change(ref.contentHash) { review in review.requeue(ref.batchID) }
        }
        if let older = open {
            open = nil
            older.timeout?.cancel()
            older.answer.resume(returning: .replaced)
        }
        if let outcome = takeNext() { return outcome }
        if timeout == 0 {
            outbox.waitClosed(at: now())
            return .ranOut
        }
        return await withCheckedContinuation { continuation in
            var waiting = OpenWait(connection: connection, answer: continuation)
            if let timeout {
                let ticket = waiting.ticket
                waiting.timeout = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(timeout)) } catch { return }
                    self?.close(.ranOut) { $0.ticket == ticket }
                }
            }
            open = waiting
        }
    }

    /// The connection `connection` closed at its client's end: a `wait`
    /// held on it is over, and the listener no longer waits.
    func connectionClosed(_ connection: UUID) {
        close(.gone) { $0.connection == connection }
    }

    /// The reply that carried `ref` couldn't be written: the batch is first
    /// in line again, for the next `wait`.
    func undelivered(_ ref: BatchRef) {
        outbox.undelivered(ref)
        deliver()
    }

    /// The app quits: the open `wait` ends with no answer, so its command
    /// connects again once the app is back.
    func stop() {
        close(.gone) { _ in true }
    }

    // MARK: - Delivery

    /// Gives the open `wait` the first batch in line, when there are both.
    private func deliver() {
        guard let waiting = open, let outcome = takeNext() else { return }
        open = nil
        waiting.timeout?.cancel()
        waiting.answer.resume(returning: outcome)
    }

    /// Ends the open `wait` with `outcome` when it's the one `matches` names.
    private func close(_ outcome: Outcome, where matches: (OpenWait) -> Bool) {
        guard let waiting = open, matches(waiting) else { return }
        open = nil
        waiting.timeout?.cancel()
        outbox.waitClosed(at: now())
        waiting.answer.resume(returning: outcome)
    }

    /// Takes the first batch in line for the open `wait`, as its payload,
    /// assembled now. A batch with nothing left to deliver (its review
    /// isn't in this run, or every comment in it is finished) leaves the
    /// line instead.
    private func takeNext() -> Outcome? {
        while outbox.isWaitOpen, let first = outbox.pending.first {
            guard let review = desk.review(of: first.contentHash), let batch = review.batch(first.batchID),
                  !review.isFinished(first.batchID)
            else {
                outbox.discard(first)
                continue
            }
            guard let ref = outbox.deliverNext(at: now()) else { return nil }
            return .batch(ref, payload: payload(of: batch, in: review).json)
        }
        return nil
    }

    /// The payload of `batch`, read at the moment the `wait` takes it. The
    /// context is in it when this listener session hasn't had it for the
    /// video, or it changed. The transcript window isn't built yet: no
    /// lines.
    private func payload(of batch: Batch, in review: VideoReview) -> BatchPayload {
        let hash = review.video.contentHash
        return BatchPayload.assemble(
            review: review, batch: batch, context: outbox.context(for: hash, text: ContextReader.text(for: review)),
            transcript: { _ in [] },
            images: { [images] comment in
                BatchPayload.Images(
                    keyframe: images.keyframe(of: comment.id, contentHash: hash).path,
                    crop: comment.region.map { _ in images.crop(of: comment.id, contentHash: hash).path }
                )
            }
        )
    }
}
