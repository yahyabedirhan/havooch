import Foundation
import Observation
import ReviewCore
import ReviewLease
import ReviewStore
import ReviewWire

/// One review's listener: it holds the review's `Outbox` (the
/// rules), the one open `wait` and the open `ask`s (held connections, like
/// a `take` waiting in line) and assembles the payload at the moment a
/// `wait` takes a send. The listener's answers (`ack`, `status`, `reply`,
/// `ask`) change the review through the `ReviewDesk` and are announced as
/// a notice. The window that holds the review reads the presence from it.
/// The `ListenerHub` makes one per review and routes to it.
@Observable
final class ListenerQueue {
    /// How a `wait` ends.
    enum Outcome: Equatable {
        /// The next send, with the JSON the command prints.
        case send(SendRef, payload: String)
        /// Its time ran out with no send.
        case ranOut
        /// A newer `wait` of the same listener took its place.
        case replaced
        /// Another agent's `wait` on the review took its place: the agent
        /// called `by` listens to it now.
        case takenOver(by: String)
        /// The person let this listener go in the Connect view (Disconnect).
        case disconnected
        /// Nobody reads the answer: its client went away, or the app quits.
        case gone
    }

    /// A listener session that replaced one that was there: the window
    /// says "Codex took over from Claude Code".
    struct Takeover: Equatable {
        /// The agent that listened before.
        var from: String
        /// The agent that listens now, and its holder key.
        var to: String
        var key: String
        var at: Date
    }

    /// The review this listener listens to. It changes once, when `project
    /// new` moves a plain video's review into a project (`rekey`).
    private(set) var key: ReviewKey
    /// When the data the listener is on opened: a session the last run
    /// left reconnects for `reconnectSeconds` after it.
    let startedAt: Date
    /// The last time a new agent replaced one that was there; nil until one does.
    private(set) var takeover: Takeover?

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

    /// What the agent does now, as `status working` with a text said it:
    /// the live line under a thread's conversation and in the footer. One
    /// per thread, the latest; never kept, since it's only true while the
    /// agent works.
    struct Activity: Equatable {
        var thread: ThreadID
        var message: MessageID
        var text: String
        var at: Date
    }

    /// The live lines by thread. `done` or `failed` on a line's message
    /// clears it, and so does a new listener session.
    private(set) var activities: [ThreadID: Activity] = [:]

    @ObservationIgnored private var open: OpenWait?
    /// The holder key the person disconnected while it had no `wait` open
    /// (it was working): its next `wait` is refused the same way, once.
    @ObservationIgnored private var letGoKey: String?
    /// The open `ask`s, by the thread each one asks on: a thread has one
    /// open question at most.
    @ObservationIgnored private var asks: [ThreadID: OpenAsk] = [:]
    /// Told each thing the agent says, and each takeover, to show it as a
    /// notice.
    @ObservationIgnored var announce: (@MainActor (Notice) -> Void)?
    /// Told each time a `wait` opens: an agent connected.
    @ObservationIgnored var connected: (@MainActor () -> Void)?
    /// The project `slug` as `config.toml` lists it now, for the payload's
    /// project block; nil for a project the file doesn't have.
    @ObservationIgnored var outline: @MainActor (String) -> ProjectOutline? = { _ in nil }
    @ObservationIgnored private let desk: ReviewDesk
    @ObservationIgnored private let layout: SupportLayout
    @ObservationIgnored private let now: @MainActor () -> Date

    /// The listener of the review `key`. It starts from the outbox the
    /// last run left for the review in the desk's library, and keeps it
    /// there.
    /// `startedAt` is when the data opened, the launch for the person's
    /// own; it's now when not given.
    init(
        key: ReviewKey, desk: ReviewDesk, layout: SupportLayout, startedAt: Date? = nil,
        now: @escaping @MainActor () -> Date = { Date() }
    ) {
        self.key = key
        self.desk = desk
        self.layout = layout
        self.now = now
        self.startedAt = startedAt ?? now()
        outbox = desk.library.loadOutbox(key)
    }

    /// The review this listener listens to became the review `new` (`project
    /// new --from`): its outbox moves to `new`'s file and names `new` in its
    /// sends, and the open `wait`, the asks and the listener session stay,
    /// so the listener keeps listening.
    func rekey(to new: ReviewKey) {
        let old = key
        guard old != new else { return }
        key = new
        let moved = outbox.rekeyed(from: old, to: new)
        if moved != outbox { outbox = moved }
        keep(outbox)
        desk.library.removeOutbox(old)
    }

    /// Saves `outbox`. One that can't be written is written with the next
    /// change; the reviews hold every send, and the next launch puts an
    /// unfinished one that's missing back in line (`Outbox.reconcile`).
    private func keep(_ outbox: Outbox) {
        do throws(Library.Failure) {
            try desk.library.save(outbox, of: key)
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

    /// How long a listener the last run left counts as reconnecting after
    /// the launch, with no word from it yet.
    static let reconnectSeconds: TimeInterval = 30

    /// The listener as the Connect view and the pill show it.
    enum Phase: Equatable {
        /// Nobody listens.
        case none
        /// The agent of `session` is there: listening or working.
        case connected(ListenerSession)
        /// The agent the last run had hasn't spoken yet in this one: it
        /// comes back on its next `wait`, until `until`.
        case reconnecting(ListenerSession, until: Date)
    }

    /// The phase at `time`. The only waiting state is a real connection
    /// state: a session the last run left, not yet heard from in this one,
    /// for `reconnectSeconds` after the data opened.
    func phase(at time: Date) -> Phase {
        guard let session = outbox.session else { return .none }
        if outbox.presence(at: time) != .absent { return .connected(session) }
        let until = startedAt.addingTimeInterval(Self.reconnectSeconds)
        if outbox.lastHeard == nil, time < until { return .reconnecting(session, until: until) }
        return .none
    }

    /// Disconnect and Forget: the person lets the listener go. Its open
    /// `wait` ends with a refusal that tells the agent to stop, its open
    /// `ask`s end, and what it took and didn't finish is first in line
    /// again, its messages `sent`, for the next agent. Nil, and nothing
    /// changes, when no listener session is there to let go.
    @discardableResult
    func disconnect() -> ListenerSession? {
        guard let session = outbox.session else { return nil }
        letGoKey = open == nil ? session.key : nil
        close(.disconnected) { _ in true }
        for (id, ask) in asks { closeAsk(id, ask.ticket, .gone) }
        for ref in outbox.letGo() {
            _ = try? desk.change(ref.review) { review in review.requeue(ref.sendID) }
        }
        activities = [:]
        takeover = nil
        return session
    }

    /// The live lines at `time`, the newest first: none while no agent is
    /// there, since a listener that went away says nothing more.
    func activities(at time: Date) -> [Activity] {
        guard outbox.presence(at: time) != .absent else { return [] }
        return activities.values.sorted { $0.at > $1.at }
    }

    /// The live line of the thread `id` at `time`; nil with none.
    func activity(on id: ThreadID, at time: Date) -> Activity? {
        guard outbox.presence(at: time) != .absent else { return nil }
        return activities[id]
    }

    /// The listener as `state` reports it at `time`.
    func report(at time: Date) -> StateReport.Listener {
        StateReport.Listener(
            presence: outbox.presence(at: time).rawValue, waitOpen: outbox.isWaitOpen, session: outbox.session?.name,
            pendingSends: outbox.pending.count, takenSends: outbox.taken.count,
            activity: activities(at: time).map { StateReport.Activity(thread: $0.thread.text, message: $0.message.text, text: $0.text) },
            tookOverFrom: takeover.flatMap { $0.key == outbox.session?.key ? $0.from : nil }
        )
    }

    // MARK: - The listener's side

    /// `havooch wait`: the next send in line, at once when there is
    /// one, else when the person sends, for up to `timeout` seconds (nil:
    /// with no limit). A `wait` from another holder than the last is a new
    /// listener session: the sends the last one took and didn't finish are
    /// first in line again, their unfinished messages `sent`. When the last
    /// one was there, the new one took over from it, and the window says
    /// so. A `wait` that's still open is replaced: one listener per review.
    func wait(by holder: Holder, timeout: Int?, connection: UUID? = nil) async -> Outcome {
        // An agent let go while it worked hears it on its next `wait`.
        if let letGoKey {
            self.letGoKey = nil
            if letGoKey == holder.key { return .disconnected }
        }
        let listener = ListenerSession(key: holder.key, name: holder.name, place: holder.place)
        let time = now()
        let last = outbox.session.flatMap { $0.key == listener.key ? nil : $0 }
        let lastWasThere = last != nil && outbox.presence(at: time) != .absent
        let requeued = outbox.waitOpened(by: listener, at: time)
        for ref in requeued {
            _ = try? desk.change(ref.review) { review in review.requeue(ref.sendID) }
        }
        // A new session starts its work over: what the last one did is past.
        if !requeued.isEmpty { activities = [:] }
        if let last, lastWasThere { tookOver(from: last.name, to: listener, at: time) }
        connected?()
        if let older = open {
            open = nil
            older.timeout?.cancel()
            older.answer.resume(returning: last == nil ? .replaced : .takenOver(by: listener.name))
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
        if desk.review(of: ref.review)?.isFinished(ref.sendID) ?? true { outbox.finished(ref) }
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

    /// `havooch ack`: the listener has the send. Its messages turn
    /// `acknowledged`, and `text` is the agent's message on General.
    func ack(_ sendID: String, text: String?) throws(AppRefusal) -> StateReport.Send {
        outbox.heard(at: now())
        guard let id = ItemID(sendID), id.kind == .send, let owner = desk.key(of: id) else {
            throw AppRefusal("no send `\(sendID)`; the send `havooch wait` printed names its id")
        }
        let before = desk.review(of: owner)?.general.messages.count ?? 0
        let send = try desk.change(owner) { [time = now(), session = outbox.session?.name] review throws(ReviewRefusal) in
            try review.acknowledge(id, text: text, session: session, now: time)
        }
        guard let review = desk.review(of: owner) else { throw AppRefusal("there's no review of \(ReviewDesk.name(owner))") }
        let count = send.messageIDs.count
        // The acknowledgement's own words, when it came with some.
        let words = review.general.messages.count > before ? review.general.messages.last?.text : nil
        notify(review.general.id, .acknowledgement, words ?? "It got your \(count) message\(count == 1 ? "" : "s").")
        return StateReport.Send(send, in: review)
    }

    /// `havooch status`: how far the listener is with a message. The
    /// send whose last message finishes is no longer taken, so the listener
    /// is back to listening. `working` with a `text` makes it the thread's
    /// live line, and with an empty one clears it; `done` and `failed`
    /// clear the line the message set.
    func status(_ messageID: String, _ state: MessageState, text: String? = nil) throws(AppRefusal) -> StateReport.Message {
        outbox.heard(at: now())
        guard let id = ItemID(messageID), id.kind == .message, let review = desk.key(of: id) else {
            throw AppRefusal("no message `\(messageID)`; the send `havooch wait` printed names each message's id")
        }
        let message = try desk.change(review) { review throws(ReviewRefusal) in try review.setState(id, state) }
        if state.isFinal {
            activities = activities.filter { $0.value.message != id }
        } else if let text, let thread = desk.review(of: review)?.threads.first(where: { $0.messages.contains { $0.id == id } })?.id {
            let words = text.trimmingCharacters(in: .whitespacesAndNewlines)
            activities[thread] = words.isEmpty ? nil : Activity(thread: thread, message: id, text: words, at: now())
        }
        if let sendID = message.sendID, desk.review(of: review)?.isFinished(sendID) == true {
            outbox.finished(SendRef(sendID: sendID, review: review))
        }
        return StateReport.Message(message, review: review, layout: layout)
    }

    /// `havooch reply`: the agent's message on the thread `id`, of the
    /// review `review`.
    func reply(on id: ThreadID, of review: ReviewKey, text: String) throws(AppRefusal) -> StateReport.Message {
        outbox.heard(at: now())
        let message = try desk.change(review) { [time = now(), session = outbox.session?.name] review throws(ReviewRefusal) in
            try review.reply(on: id, text: text, session: session, now: time)
        }
        notify(id, .message, message.text)
        return StateReport.Message(message, review: review, layout: layout)
    }

    /// `havooch ask`: the agent's question on the thread `id`, of the
    /// review `review`, with its quick-reply `choices`, held until the person
    /// answers it, for up to `waitSeconds` (nil: with no limit). When the
    /// time runs out the question stays open, and an answer that comes
    /// later stays on the thread.
    func ask(
        on id: ThreadID, of review: ReviewKey, question: String, choices: [String] = [], waitSeconds: Int?, connection: UUID? = nil
    ) async throws(AppRefusal) -> Asked {
        outbox.heard(at: now())
        let time = now()
        let message = try desk.change(review) { [session = outbox.session?.name] review throws(ReviewRefusal) in
            try review.ask(on: id, question: question, choices: choices, session: session, now: time)
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

    /// The agent `to` took over from `from`, which was there: kept for
    /// `state`, and said on the stage of the window that holds the review,
    /// on its General thread. A review with none yet has no window to say it in.
    private func tookOver(from: String, to: ListenerSession, at time: Date) {
        takeover = Takeover(from: from, to: to.name, key: to.key, at: time)
        guard let general = review?.general.id else { return }
        announce?(Notice(thread: general, kind: .takeover, agent: to.name, text: "\(to.name) took over from \(from)", at: time))
    }

    /// The review this listener listens to, as the desk keeps it; nil
    /// before it has one.
    private var review: Review? {
        desk.review(of: key)
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
            guard let review = desk.review(of: first.review), let send = review.send(first.sendID),
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
    /// review, or it changed. Each thread's transcript is the one the send
    /// kept. A project's review carries the project's list as it is now.
    private func payload(of send: Send, in review: Review) -> SendPayload {
        let key = review.key
        return SendPayload.assemble(
            review: review, send: send, context: outbox.context(for: key.contextKey, text: ContextReader.text(for: review)),
            images: SendPayload.Images(
                keyframe: { [layout] in layout.keyframe(of: $0, on: key)?.path },
                crop: { [layout] in layout.crop(of: $0, on: key)?.path }
            ),
            project: key.slug.flatMap(outline)
        )
    }
}
