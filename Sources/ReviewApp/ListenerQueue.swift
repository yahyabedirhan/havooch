import Foundation
import Observation
import ReviewCore
import ReviewStore
import ReviewWire

/// The listener's side of the app: it holds the `Outbox` (the rules), the
/// one open `wait` and the open `ask`s (held connections, like a `take`
/// waiting in line) and assembles the payload at the moment a `wait` takes
/// a batch. The listener's answers (`ack`, `status`, `reply`, `ask`) change
/// a review through the `ReviewDesk` and are announced as a notice. The
/// views read the presence from it.
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
    /// What of it outlives a run is saved whenever it changes.
    private(set) var outbox: Outbox {
        didSet {
            guard !outbox.isKeptAs(oldValue) else { return }
            keep(outbox)
        }
    }

    /// The `wait` that's held open until a batch is sent.
    private struct OpenWait {
        var ticket = UUID()
        /// The connection it came over, to tell when its client goes away.
        var connection: UUID?
        var answer: CheckedContinuation<Outcome, Never>
        /// Ends the wait when its time runs out; cancelled once it's answered.
        var timeout: Task<Void, Never>?
    }

    /// How an `ask` ends.
    enum Asked: Equatable {
        /// The person's answer.
        case answered(StateReport.Message)
        /// Its time ran out with no answer; the question stays open.
        case ranOut
        /// Nobody reads the answer: its client went away, or the app quits.
        case gone
    }

    /// An `ask` that's held open until the person answers.
    private struct OpenAsk {
        var ticket = UUID()
        var connection: UUID?
        var answer: CheckedContinuation<Asked, Never>
        var timeout: Task<Void, Never>?
    }

    @ObservationIgnored private var open: OpenWait?
    /// The open `ask`s, by the comment each one asks about: a comment has
    /// one open question at most.
    @ObservationIgnored private var asks: [ItemID: OpenAsk] = [:]
    /// Told each thing the agent says, to show it as a notice.
    @ObservationIgnored var announce: (@MainActor (Notice) -> Void)?
    @ObservationIgnored private let desk: ReviewDesk
    @ObservationIgnored private let images: ImageFiles
    @ObservationIgnored private let now: @MainActor () -> Date
    /// Where a comment's transcript lines come from; with none, a comment
    /// gets no lines. The app's model sets it.
    @ObservationIgnored var transcripts: TranscriptDesk?

    /// It starts from the outbox the last run left in the desk's library,
    /// and keeps it there.
    init(desk: ReviewDesk, images: ImageFiles, now: @escaping @MainActor () -> Date = { Date() }) {
        self.desk = desk
        self.images = images
        self.now = now
        outbox = desk.library.loadOutbox()
    }

    /// Saves `outbox`. One that can't be written is written with the next
    /// change; the reviews hold every batch, and the next launch puts an
    /// unfinished one that's missing back in line (`Outbox.reconcile`).
    private func keep(_ outbox: Outbox) {
        do throws(Library.Failure) {
            try desk.library.save(outbox)
        } catch {
            FileHandle.standardError.write(Data("\(AppIdentity.appName): \(error.reason)\n".utf8))
        }
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
    /// held on it is over, and the listener no longer waits. An `ask` held
    /// on it is over too; its question stays in the thread.
    func connectionClosed(_ connection: UUID) {
        close(.gone) { $0.connection == connection }
        for (id, ask) in asks where ask.connection == connection { closeAsk(id, ask.ticket, .gone) }
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
        for (id, ask) in asks { closeAsk(id, ask.ticket, .gone) }
    }

    // MARK: - The listener's answers

    /// `video-review ack`: the listener has the batch. Its comments turn
    /// `acknowledged`, and `text` is a message for the full batch.
    func ack(_ batchID: String, text: String?) throws(AppRefusal) -> StateReport.Batch {
        outbox.heard(at: now())
        guard let id = ItemID(batchID), id.kind == .batch, let hash = desk.contentHash(of: id) else {
            throw AppRefusal(ReviewRefusal.unknownBatch(batchID).line)
        }
        let messageID = ItemID.make(.message)
        let batch = try desk.change(hash) { [time = now()] review throws(ReviewRefusal) in
            try review.acknowledge(id, text: text, messageID: messageID, at: time)
        }
        let count = batch.commentIDs.count
        // The acknowledgement's own words, when it came with some.
        let words = batch.messages.last.flatMap { $0.id == messageID ? $0.text : nil }
        notify(.batch(id), .acknowledgement, words ?? "It got your \(count) comment\(count == 1 ? "" : "s").")
        return StateReport.Batch(batch)
    }

    /// `video-review status`: how far the listener is with a comment. The
    /// batch whose last comment finishes is no longer taken, so the
    /// listener is back to listening.
    func status(_ commentID: String, _ state: CommentState) throws(AppRefusal) -> StateReport.Comment {
        outbox.heard(at: now())
        let (id, hash) = try comment(commentID)
        let comment = try desk.change(hash) { review throws(ReviewRefusal) in try review.setStatus(id, state) }
        if let batchID = comment.batchID, desk.review(of: hash)?.isFinished(batchID) == true {
            outbox.finished(BatchRef(batchID: batchID, contentHash: hash))
        }
        return StateReport.Comment(comment, contentHash: hash, images: images)
    }

    /// `video-review reply`: the agent's message on a comment's thread, or
    /// for the full batch when `target` is a batch's id.
    func reply(to target: String, text: String) throws(AppRefusal) -> StateReport.Message {
        outbox.heard(at: now())
        guard let id = ItemID(target), id.kind != .message, let hash = desk.contentHash(of: id) else {
            throw AppRefusal("no comment or batch `\(target)`; the batch `video-review wait` printed names their ids")
        }
        let time = now()
        let message = try desk.change(hash) { review throws(ReviewRefusal) in
            try review.reply(to: id, text: text, messageID: ItemID.make(.message), at: time)
        }
        notify(id.kind == .batch ? .batch(id) : .comment(id), .message, message.text)
        return StateReport.Message(message)
    }

    /// `video-review ask`: the agent's question on a comment's thread,
    /// held until the person answers it, for up to `waitSeconds` (nil: with
    /// no limit). When the time runs out the question stays open, and an
    /// answer that comes later stays in the thread.
    func ask(_ commentID: String, question: String, waitSeconds: Int?, connection: UUID? = nil) async throws(AppRefusal) -> Asked {
        outbox.heard(at: now())
        let (id, hash) = try comment(commentID)
        let time = now()
        let message = try desk.change(hash) { review throws(ReviewRefusal) in
            try review.ask(id, question: question, messageID: ItemID.make(.message), at: time)
        }
        notify(.comment(id), .question, message.text)
        if waitSeconds == 0 { return .ranOut }
        outbox.askOpened(at: time)
        return await withCheckedContinuation { continuation in
            var asking = OpenAsk(connection: connection, answer: continuation)
            if let waitSeconds {
                let ticket = asking.ticket
                asking.timeout = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(waitSeconds)) } catch { return }
                    self?.closeAsk(id, ticket, .ranOut)
                }
            }
            asks[id] = asking
        }
    }

    /// The person answered the open question of the comment `id`: the
    /// `ask` that waits for it, when one still does, exits with the answer.
    func answered(_ id: ItemID, with message: ThreadMessage) {
        guard let ask = asks[id] else { return }
        closeAsk(id, ask.ticket, .answered(StateReport.Message(message)))
    }

    /// Ends the open `ask` on the comment `id` with `outcome`, when it's
    /// still the one `ticket` names.
    private func closeAsk(_ id: ItemID, _ ticket: UUID, _ outcome: Asked) {
        guard let ask = asks[id], ask.ticket == ticket else { return }
        asks[id] = nil
        ask.timeout?.cancel()
        outbox.askClosed(at: now())
        ask.answer.resume(returning: outcome)
    }

    /// The comment a listener's command names, and its video. The command
    /// names no video, so the library's index of ids finds it.
    private func comment(_ text: String) throws(AppRefusal) -> (ItemID, String) {
        guard let id = ItemID(text), id.kind == .comment, let hash = desk.contentHash(of: id) else {
            throw AppRefusal("no comment `\(text)`; the batch `video-review wait` printed names each comment's id")
        }
        return (id, hash)
    }

    private func notify(_ subject: Notice.Subject, _ kind: Notice.Kind, _ text: String) {
        announce?(Notice(subject: subject, kind: kind, agent: outbox.session?.name ?? "The agent", text: text, at: now()))
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
    /// assembled now. A batch with nothing left to deliver (it has no
    /// review that reads, or every comment in it is finished) leaves the
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
    /// video, or it changed. Each comment gets the transcript lines that
    /// exist then.
    private func payload(of batch: Batch, in review: VideoReview) -> BatchPayload {
        let hash = review.video.contentHash
        return BatchPayload.assemble(
            review: review, batch: batch, context: outbox.context(for: hash, text: ContextReader.text(for: review)),
            transcript: { [transcripts] comment in transcripts?.lines(around: comment.time, of: review.video) ?? [] },
            images: { [images] comment in
                BatchPayload.Images(
                    keyframe: images.keyframe(of: comment.id, contentHash: hash).path,
                    crop: comment.region.map { _ in images.crop(of: comment.id, contentHash: hash).path }
                )
            }
        )
    }
}
