import Foundation
import Observation
import ReviewCore
import ReviewLease
import ReviewStore
import ReviewWire

/// The listener's side of the app: it holds the `Outbox` (the rules), the
/// one open `wait` and the open `ask`s (held connections, like a `take`
/// waiting in line) and assembles the payload at the moment a `wait` takes
/// a send. The listener's answers (`ack`, `status`, `reply`, `ask`) change
/// a review through the `ReviewDesk` and are announced as a notice. The
/// views read the presence from it.
@Observable
final class ListenerQueue {
    /// How a `wait` ends.
    enum Outcome: Equatable {
        /// The next send, with the JSON the command prints.
        case send(SendRef, payload: String)
        /// Its time ran out with no send.
        case ranOut
        /// A newer `wait` took its place.
        case replaced
        /// Nobody reads the answer: its client went away, or the app quits.
        case gone
    }

    /// The pending and taken sends, the listener session and its presence.
    /// What of it outlives a run is saved whenever it changes.
    private(set) var outbox: Outbox {
        didSet {
            guard !outbox.isKeptAs(oldValue) else { return }
            keep(outbox)
        }
    }

    /// The `wait` that's held open until a send is made.
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
    /// The open `ask`s, by the thread each one asks on: a thread has one
    /// open question at most.
    @ObservationIgnored private var asks: [ThreadID: OpenAsk] = [:]
    /// Told each thing the agent says, to show it as a notice.
    @ObservationIgnored var announce: (@MainActor (Notice) -> Void)?
    @ObservationIgnored private let desk: ReviewDesk
    @ObservationIgnored private let layout: SupportLayout
    @ObservationIgnored private let now: @MainActor () -> Date

    /// It starts from the outbox the last run left in the desk's library,
    /// and keeps it there.
    init(desk: ReviewDesk, layout: SupportLayout, now: @escaping @MainActor () -> Date = { Date() }) {
        self.desk = desk
        self.layout = layout
        self.now = now
        outbox = desk.library.loadOutbox()
    }

    /// Saves `outbox`. One that can't be written is written with the next
    /// change; the reviews hold every send, and the next launch puts an
    /// unfinished one that's missing back in line (`Outbox.reconcile`).
    private func keep(_ outbox: Outbox) {
        do throws(Library.Failure) {
            try desk.library.save(outbox)
        } catch {
            FileHandle.standardError.write(Data("\(AppIdentity.appName): \(error.reason)\n".utf8))
        }
    }

    // MARK: - The person's side

    /// A send the person made: the open `wait` gets it at once, else it
    /// waits in line for the next one.
    func enqueue(_ ref: SendRef) {
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
            pendingSends: outbox.pending.count, takenSends: outbox.taken.count
        )
    }

    // MARK: - The listener's side

    /// `video-review wait`: the next send in line, at once when there is
    /// one, else when the person sends, for up to `timeout` seconds (nil:
    /// with no limit). A `wait` from another holder than the last is a new
    /// listener session: the sends the last one took and didn't finish are
    /// first in line again, their unfinished messages `sent`. A
    /// `wait` that's still open is replaced: one listener at a time.
    func wait(by holder: Holder, timeout: Int?, connection: UUID? = nil) async -> Outcome {
        let listener = ListenerSession(key: holder.key, name: holder.name, place: holder.place)
        for ref in outbox.waitOpened(by: listener, at: now()) {
            _ = try? desk.change(ref.contentHash) { review in review.requeue(ref.sendID) }
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

    /// The reply that carried `ref` was written: the listener has the
    /// send, which is taken from now on. One the listener finished before
    /// this was heard leaves the line.
    func written(_ ref: SendRef) {
        outbox.written(ref)
        if desk.review(of: ref.contentHash)?.isFinished(ref.sendID) ?? true { outbox.finished(ref) }
        // A send that stayed in line (its session ended meanwhile) is free for the next `wait`.
        deliver()
    }

    /// The reply that carried `ref` couldn't be written: the send is first
    /// in line again, for the next `wait`.
    func undelivered(_ ref: SendRef) {
        outbox.undelivered(ref)
        deliver()
    }

    /// Whether the listener has the send `id` or is being handed it:
    /// taken, or in flight.
    func isDelivered(_ id: String) -> Bool {
        outbox.taken.contains { $0.sendID.text == id } || outbox.inFlight.keys.contains { $0.sendID.text == id }
    }

    /// The app quits: the open `wait` ends with no answer, so its command
    /// connects again once the app is back.
    func stop() {
        close(.gone) { _ in true }
        for (id, ask) in asks { closeAsk(id, ask.ticket, .gone) }
    }

    // MARK: - The listener's answers

    /// `video-review ack`: the listener has the send. Its messages turn
    /// `acknowledged`, and `text` is the agent's message on General.
    func ack(_ sendID: String, text: String?) throws(AppRefusal) -> StateReport.Send {
        outbox.heard(at: now())
        guard let id = ItemID(sendID), id.kind == .send, let hash = desk.contentHash(of: id) else {
            throw AppRefusal("no send `\(sendID)`; the send `video-review wait` printed names its id")
        }
        let before = desk.review(of: hash)?.general.messages.count ?? 0
        let send = try desk.change(hash) { [time = now()] review throws(ReviewRefusal) in
            try review.acknowledge(id, text: text, now: time)
        }
        guard let review = desk.review(of: hash) else { throw AppRefusal("there's no review of the video \(hash)") }
        let count = send.messageIDs.count
        // The acknowledgement's own words, when it came with some.
        let words = review.general.messages.count > before ? review.general.messages.last?.text : nil
        notify(review.general.id, .acknowledgement, words ?? "It got your \(count) message\(count == 1 ? "" : "s").")
        return StateReport.Send(send, in: review)
    }

    /// `video-review status`: how far the listener is with a message. The
    /// send whose last message finishes is no longer taken, so the listener
    /// is back to listening.
    func status(_ messageID: String, _ state: MessageState) throws(AppRefusal) -> StateReport.Message {
        outbox.heard(at: now())
        guard let id = ItemID(messageID), id.kind == .message, let hash = desk.contentHash(of: id) else {
            throw AppRefusal("no message `\(messageID)`; the send `video-review wait` printed names each message's id")
        }
        let message = try desk.change(hash) { review throws(ReviewRefusal) in try review.setState(id, state) }
        if let sendID = message.sendID, desk.review(of: hash)?.isFinished(sendID) == true {
            outbox.finished(SendRef(sendID: sendID, contentHash: hash))
        }
        return StateReport.Message(message, contentHash: hash, layout: layout)
    }

    /// `video-review reply`: the agent's message on a thread.
    func reply(on thread: String, text: String) throws(AppRefusal) -> StateReport.Message {
        outbox.heard(at: now())
        let (id, hash) = try desk.threadID(thread)
        let message = try desk.change(hash) { [time = now()] review throws(ReviewRefusal) in
            try review.reply(on: id, text: text, now: time)
        }
        notify(id, .message, message.text)
        return StateReport.Message(message, contentHash: hash, layout: layout)
    }

    /// `video-review ask`: the agent's question on a thread, held until the
    /// person answers it, for up to `waitSeconds` (nil: with no limit).
    /// When the time runs out the question stays open, and an answer that
    /// comes later stays on the thread.
    func ask(on thread: String, question: String, waitSeconds: Int?, connection: UUID? = nil) async throws(AppRefusal) -> Asked {
        outbox.heard(at: now())
        let (id, hash) = try desk.threadID(thread)
        let time = now()
        let message = try desk.change(hash) { review throws(ReviewRefusal) in
            try review.ask(on: id, question: question, now: time)
        }
        notify(id, .question, message.text)
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

    /// The person answered the open question on the thread `id`: the `ask`
    /// that waits for it, when one still does, exits with the answer.
    func answered(_ id: ThreadID, with message: StateReport.Message) {
        guard let ask = asks[id] else { return }
        closeAsk(id, ask.ticket, .answered(message))
    }

    /// Ends the open `ask` on the thread `id` with `outcome`, when it's
    /// still the one `ticket` names.
    private func closeAsk(_ id: ThreadID, _ ticket: UUID, _ outcome: Asked) {
        guard let ask = asks[id], ask.ticket == ticket else { return }
        asks[id] = nil
        ask.timeout?.cancel()
        outbox.askClosed(at: now())
        ask.answer.resume(returning: outcome)
    }

    private func notify(_ thread: ThreadID, _ kind: Notice.Kind, _ text: String) {
        announce?(Notice(thread: thread, kind: kind, agent: outbox.session?.name ?? "The agent", text: text, at: now()))
    }

    // MARK: - Delivery

    /// Gives the open `wait` the first send in line, when there are both.
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

    /// Hands the first send in line that isn't in flight to the open
    /// `wait`, as its payload, assembled now. It's taken once the reply is
    /// written (`written`). A send with nothing left to deliver (it has no
    /// review that reads, or every message in it is finished) leaves the
    /// line instead.
    private func takeNext() -> Outcome? {
        while outbox.isWaitOpen, let first = outbox.pending.first(where: { outbox.inFlight[$0] == nil }) {
            guard let review = desk.review(of: first.contentHash), let send = review.send(first.sendID),
                  !review.isFinished(first.sendID)
            else {
                outbox.discard(first)
                continue
            }
            guard let ref = outbox.handOut(at: now()) else { return nil }
            return .send(ref, payload: payload(of: send, in: review).json)
        }
        return nil
    }

    /// The payload of `send`, read at the moment the `wait` takes it. The
    /// context is in it when this listener session hasn't had it for the
    /// video, or it changed. Each thread's transcript is the one the send
    /// kept.
    private func payload(of send: Send, in review: VideoReview) -> SendPayload {
        let hash = review.video.contentHash
        return SendPayload.assemble(
            review: review, send: send, context: outbox.context(for: hash, text: ContextReader.text(for: review)),
            images: SendPayload.Images(
                keyframe: { [layout] in layout.keyframe($0.id, of: hash).path },
                crop: { [layout] in layout.crop($0.id, of: hash).path }
            )
        )
    }
}
