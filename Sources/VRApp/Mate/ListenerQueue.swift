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

    /// What a `reply` was posted on: a comment's thread, or a batch's.
    enum ReplyTarget: Equatable, Sendable {
        case comment(Comment)
        case batch(Batch)
    }

    /// How an `ask` ends.
    enum AskOutcome: Equatable, Sendable {
        /// The person's answer.
        case answer(String)
        /// Its `--wait` ran out with no answer; the question stays open.
        case timedOut
        case refused(String)
        /// Its connection closed: nobody reads the answer.
        case gone
    }

    /// One open `ask`: the question it waits on, and how it gets its answer.
    private struct Asker {
        var ticket: UUID
        var comment: CommentID
        var question: String
        var answer: CheckedContinuation<AskOutcome, Never>
        /// Ends the ask when its `--wait` runs out; cancelled once it's answered.
        var timeout: Task<Void, Never>?
    }

    /// The listener session and the batches on their way, as
    /// `listener.json` keeps them: read as the queue is made, and written
    /// at each change, through `record`.
    private(set) var ledger: ListenerLedger
    /// The open `wait`s, oldest first.
    private var waiters: [Waiter] = []
    /// The open `ask`s, oldest first.
    private var askers: [Asker] = []
    /// Told each agent message as it arrives, for the window's notice.
    @ObservationIgnored var announce: @MainActor (Notice) -> Void = { _ in }
    /// The batches whose reply is being written: handed to a `wait`, not
    /// yet taken, and so not handed to a second one.
    private var inFlight: Set<BatchID> = []
    /// Set once the app quits: a `wait` that comes then is refused.
    private var closed = false
    @ObservationIgnored private let desk: ReviewDesk
    @ObservationIgnored private let now: @MainActor () -> Date

    static let quittingRefusal = "video-review is quitting"

    /// Takes up where the last run stopped: the ledger as it was kept,
    /// brought in line with the reviews. A batch a listener had taken
    /// stays taken by it; one that is pending has its comments `sent`.
    init(desk: ReviewDesk, now: @escaping @MainActor () -> Date) {
        self.desk = desk
        self.now = now
        ledger = desk.store.loadLedger()
        record { $0.reconcile(with: desk.all) }
        for delivery in ledger.deliveries where delivery.isPending {
            _ = try? desk.change(delivery.video) { review in review.requeue(delivery.batch) }
        }
    }

    /// The one way the ledger changes: `change` is applied, and a ledger
    /// that differs is saved. A ledger that can't be saved goes on in
    /// memory, and is saved with its next change.
    @discardableResult
    private func record<T>(_ change: (inout ListenerLedger) -> T) -> T {
        var changed = ledger
        let result = change(&changed)
        guard changed != ledger else { return result }
        ledger = changed
        do {
            try desk.store.save(changed)
        } catch {
            NSLog("video-review: can't keep the listener ledger: %@", error.localizedDescription)
        }
        return result
    }

    // MARK: - What the window and `state` show

    /// The listener there is, or was last.
    var session: ListenerLedger.Session? { ledger.session }

    /// Whether a listener is there at `time`.
    func presence(at time: Date) -> Presence {
        ledger.presence(waitOpen: connected, now: time)
    }

    /// Whether the listener holds a connection open: a `wait`, or an `ask`
    /// that waits for its answer. Either shows it is there.
    private var connected: Bool { !waiters.isEmpty || !askers.isEmpty }

    /// Whether a listener is there now.
    var presence: Presence { presence(at: now()) }

    /// Whether presence can change by time alone: a listener with a batch
    /// and no `wait` open is `working` only for a while after its last command.
    var presenceRunsOut: Bool { !connected && ledger.hasTaken }

    /// Where `batch` stands on its way to the listener.
    func standing(of batch: BatchID) -> ListenerLedger.Standing {
        ledger.standing(of: batch)
    }

    // MARK: - Sending

    /// `batch` of `video` was sent: it goes to the oldest open `wait`, or
    /// waits for the next one.
    func enqueue(_ batch: Batch, video: VideoInfo) {
        record { $0.enqueue(batch.id, video: video.contentHash, sentAt: batch.sentAt) }
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
        do throws(ActionError) {
            try admit(holder)
        } catch {
            return .refused(error.message)
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

    /// The first step of every listener command: `holder` is the listener
    /// from now on. Refused while the app quits, and while another
    /// listener's `wait` is open. A new listener (another key than the
    /// session's) starts a new session: the batches the one before took and
    /// didn't finish are pending again, their unfinished comments `sent`.
    private func admit(_ holder: Holder) throws(ActionError) {
        guard !closed else { throw .listener(Self.quittingRefusal) }
        if let open = waiters.first(where: { $0.holder.key != holder.key }) {
            throw .listener("\(open.holder.name) in \(open.holder.place) is already listening; one listener at a time")
        }
        let time = now()
        let requeued = record { $0.attach((key: holder.key, name: holder.name, place: holder.place), now: time) }
        for delivery in requeued {
            // A review this run doesn't have has nothing to put back.
            _ = try? desk.change(delivery.video) { review in review.requeue(delivery.batch) }
        }
        if !requeued.isEmpty { deliverIfPossible() }
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
                record { $0.finish(delivery.batch) }
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
        let time = now()
        record { $0.delivered(handed.batch, to: handed.listener, context: handed.context, now: time) }
        // Left pending when its listener is no longer the session: the next `wait` gets it.
        deliverIfPossible()
    }

    /// The reply carrying `handed` couldn't be written (its listener had
    /// gone): the batch is still pending, for the next `wait`.
    func undelivered(_ handed: Handed) {
        inFlight.remove(handed.batch)
        deliverIfPossible()
    }

    // MARK: - Answering

    /// `ack`: the listener has the batch `id`. Its sent comments are
    /// acknowledged, and `text` is a message for the whole batch.
    func acknowledge(_ id: String, text: String?, holder: Holder) throws(ActionError) -> Batch {
        try admit(holder)
        guard let hash = desk.hash(naming: id) else { throw .review(.unknownBatch(id)) }
        let time = now()
        let before = desk.review(hash)?.batches.first { $0.id.rawValue == id }?.thread.count
        let batch = try desk.change(hash) { review throws(ReviewError) in
            try review.acknowledge(BatchID(rawValue: id), text: text, now: time)
        }
        if let said = batch.thread.last, batch.thread.count != before {
            announce(Notice(batch: batch.id, comment: nil, time: nil, kind: said.kind, text: said.text))
        }
        return batch
    }

    /// `status`: the comment `id` is `working`, `done` or `failed`. The
    /// status that finishes its batch takes the batch out of the ledger.
    func setStatus(_ id: String, _ state: String, holder: Holder) throws(ActionError) -> Comment {
        try admit(holder)
        guard let next = CommentState(rawValue: state), [.working, .done, .failed].contains(next) else {
            throw .listener("no status `\(state)`; it takes `working`, `done` or `failed`")
        }
        guard let hash = desk.hash(naming: id) else { throw .review(.unknownComment(id)) }
        let comment = try desk.change(hash) { review throws(ReviewError) in
            try review.setStatus(CommentID(rawValue: id), to: next)
        }
        if let batch = comment.batch, desk.review(hash)?.isFinished(batch) == true { record { $0.finish(batch) } }
        return comment
    }

    /// `reply`: a message in the thread of the comment `id`, or, for a
    /// batch's id, a message for the whole batch.
    func reply(_ id: String, text: String, holder: Holder) throws(ActionError) -> ReplyTarget {
        try admit(holder)
        let time = now()
        if Self.namesBatch(id) {
            guard let hash = desk.hash(naming: id) else { throw .review(.unknownBatch(id)) }
            let batch = try desk.change(hash) { review throws(ReviewError) in
                try review.reply(toBatch: BatchID(rawValue: id), text: text, now: time)
            }
            if let said = batch.thread.last {
                announce(Notice(batch: batch.id, comment: nil, time: nil, kind: said.kind, text: said.text))
            }
            return .batch(batch)
        }
        guard let hash = desk.hash(naming: id) else { throw .review(.unknownComment(id)) }
        let comment = try desk.change(hash) { review throws(ReviewError) in
            try review.reply(toComment: CommentID(rawValue: id), text: text, now: time)
        }
        announce(comment)
        return .comment(comment)
    }

    /// Whether `id` is written as a batch's (`7f3a9c21-b1`), not a comment's.
    private static func namesBatch(_ id: String) -> Bool {
        id.dropFirst(VideoPrefix.length).hasPrefix("-b")
    }

    /// The window's notice for the last message in `comment`'s thread.
    private func announce(_ comment: Comment) {
        guard let said = comment.thread.last, let batch = comment.batch else { return }
        announce(Notice(batch: batch, comment: comment.id, time: comment.time, kind: said.kind, text: said.text))
    }

    /// `ask`: a question in the thread of the comment `id`, answered with
    /// what the person answers. The caller stays suspended meanwhile.
    /// Without `wait` it waits without limit. The same text as the
    /// comment's latest question attaches to that question: nothing is
    /// posted again, and an answer that is already there is returned at
    /// once, so a listener whose wait ran out asks again and loses
    /// nothing. Another question on the comment ends the asks that waited
    /// on the one before.
    func ask(_ id: String, question: String, wait: Int?, holder: Holder) async -> AskOutcome {
        let comment: Comment
        do throws(ActionError) {
            try admit(holder)
            guard let hash = desk.hash(naming: id) else { throw .review(.unknownComment(id)) }
            let time = now()
            let before = desk.review(hash)?.comments.first { $0.id.rawValue == id }?.thread.count
            comment = try desk.change(hash) { review throws(ReviewError) in
                try review.ask(CommentID(rawValue: id), question: question, now: time)
            }
            if comment.thread.count != before { announce(comment) }
        } catch {
            return .refused(error.message)
        }
        if let answer = comment.lastAnswer { return .answer(answer.text) }
        guard let asked = comment.lastQuestion?.text else { return .refused(ReviewError.noOpenQuestion(comment.id).message) }
        for asker in askers where asker.comment == comment.id && asker.question != asked {
            endAsk(asker.ticket, with: .refused("another question was asked on \(id) since: `\(asked)`"))
        }
        if wait == 0 { return .timedOut }
        let ticket = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let running = wait.map { seconds in
                    Task { [weak self] in
                        do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
                        self?.endAsk(ticket, with: .timedOut)
                    }
                }
                askers.append(Asker(ticket: ticket, comment: comment.id, question: asked, answer: continuation, timeout: running))
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.endAsk(ticket, with: .gone) }
        }
    }

    /// The person answered the question on `comment`, in the window or
    /// through `thread answer`: every `ask` that waits on it gets the answer.
    func answered(_ comment: Comment) {
        guard let answer = comment.lastAnswer else { return }
        for asker in askers where asker.comment == comment.id {
            endAsk(asker.ticket, with: .answer(answer.text))
        }
    }

    /// Ends the open `ask` `ticket` with `outcome`, unless it was answered
    /// already.
    private func endAsk(_ ticket: UUID, with outcome: AskOutcome) {
        guard let index = askers.firstIndex(where: { $0.ticket == ticket }) else { return }
        let asker = askers.remove(at: index)
        asker.timeout?.cancel()
        asker.answer.resume(returning: outcome)
    }

    /// The app quits: every open `wait` and `ask` hears why, instead of a
    /// dropped connection, and a later one is refused.
    func quitting() {
        closed = true
        for waiter in waiters { end(waiter.ticket, with: .refused(Self.quittingRefusal)) }
        for asker in askers { endAsk(asker.ticket, with: .refused(Self.quittingRefusal)) }
    }
}
