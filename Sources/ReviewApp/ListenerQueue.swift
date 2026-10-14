import Foundation
import Observation
import ReviewCore
import ReviewLease
import ReviewStore
import ReviewWire

@Observable
final class ListenerQueue {
    enum Outcome: Equatable {
        case send(SendRef, payload: String)
        case ranOut
        case replaced
        case takenOver(by: String)
        case disconnected
        case gone
    }

    struct Takeover: Equatable {
        var from: String
        var to: String
        var key: String
        var at: Date
    }

    private(set) var key: ReviewKey
    let startedAt: Date
    private(set) var takeover: Takeover?

    private(set) var outbox: Outbox {
        didSet {
            guard !outbox.isKeptAs(oldValue) else { return }
            keep(outbox)
        }
    }

    private struct OpenWait {
        var ticket = UUID()
        var connection: UUID?
        var answer: CheckedContinuation<Outcome, Never>
        var timeout: Task<Void, Never>?
    }

    enum Asked: Equatable {
        case answered(StateReport.Message)
        case ranOut
        case gone
    }

    private struct OpenAsk {
        var ticket = UUID()
        var connection: UUID?
        var answer: CheckedContinuation<Asked, Never>
        var timeout: Task<Void, Never>?
    }

    struct Activity: Equatable {
        var thread: ThreadID
        var message: MessageID
        var text: String
        var at: Date
    }

    private(set) var activities: [ThreadID: Activity] = [:]

    @ObservationIgnored private var open: OpenWait?
    @ObservationIgnored private var letGoKey: String?
    @ObservationIgnored private var asks: [ThreadID: OpenAsk] = [:]
    @ObservationIgnored var announce: (@MainActor (Notice) -> Void)?
    @ObservationIgnored var connected: (@MainActor () -> Void)?
    @ObservationIgnored var outline: @MainActor (String) -> ProjectOutline? = { _ in nil }
    @ObservationIgnored private let desk: ReviewDesk
    @ObservationIgnored private let layout: SupportLayout
    @ObservationIgnored private let now: @MainActor () -> Date

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

    func rekey(to new: ReviewKey) {
        let old = key
        guard old != new else { return }
        key = new
        let moved = outbox.rekeyed(from: old, to: new)
        if moved != outbox { outbox = moved }
        keep(outbox)
        desk.library.removeOutbox(old)
    }

    private func keep(_ outbox: Outbox) {
        do throws(Library.Failure) {
            try desk.library.save(outbox, of: key)
        } catch {
            FileHandle.standardError.write(Data("\(AppIdentity.appName): \(error.reason)\n".utf8))
        }
    }

    func enqueue(_ ref: SendRef) {
        outbox.enqueue(ref)
        deliver()
    }

    func presence(at time: Date) -> Presence {
        outbox.presence(at: time)
    }

    static let reconnectSeconds: TimeInterval = 30

    enum Phase: Equatable {
        case none
        case connected(ListenerSession)
        case reconnecting(ListenerSession, until: Date)
    }

    func phase(at time: Date) -> Phase {
        guard let session = outbox.session else { return .none }
        if outbox.presence(at: time) != .absent { return .connected(session) }
        let until = startedAt.addingTimeInterval(Self.reconnectSeconds)
        if outbox.lastHeard == nil, time < until { return .reconnecting(session, until: until) }
        return .none
    }

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

    func activities(at time: Date) -> [Activity] {
        guard outbox.presence(at: time) != .absent else { return [] }
        return activities.values.sorted { $0.at > $1.at }
    }

    func activity(on id: ThreadID, at time: Date) -> Activity? {
        guard outbox.presence(at: time) != .absent else { return nil }
        return activities[id]
    }

    func report(at time: Date) -> StateReport.Listener {
        StateReport.Listener(
            presence: outbox.presence(at: time).rawValue, waitOpen: outbox.isWaitOpen, session: outbox.session?.name,
            pendingSends: outbox.pending.count, takenSends: outbox.taken.count,
            activity: activities(at: time).map { StateReport.Activity(thread: $0.thread.text, message: $0.message.text, text: $0.text) },
            tookOverFrom: takeover.flatMap { $0.key == outbox.session?.key ? $0.from : nil }
        )
    }

    func wait(by holder: Holder, timeout: Int?, connection: UUID? = nil) async -> Outcome {
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

    func connectionClosed(_ connection: UUID) {
        close(.gone) { $0.connection == connection }
        for (id, ask) in asks where ask.connection == connection { closeAsk(id, ask.ticket, .gone) }
    }

    func written(_ ref: SendRef) {
        outbox.written(ref)
        if desk.review(of: ref.review)?.isFinished(ref.sendID) ?? true { outbox.finished(ref) }
        deliver()
    }

    func undelivered(_ ref: SendRef) {
        outbox.undelivered(ref)
        deliver()
    }

    func isDelivered(_ id: String) -> Bool {
        outbox.taken.contains { $0.sendID.text == id } || outbox.inFlight.keys.contains { $0.sendID.text == id }
    }

    func stop() {
        close(.gone) { _ in true }
        for (id, ask) in asks { closeAsk(id, ask.ticket, .gone) }
    }

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
        let words = review.general.messages.count > before ? review.general.messages.last?.text : nil
        notify(review.general.id, .acknowledgement, words ?? "It got your \(count) message\(count == 1 ? "" : "s").")
        return StateReport.Send(send, in: review)
    }

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

    func reply(on id: ThreadID, of review: ReviewKey, text: String) throws(AppRefusal) -> StateReport.Message {
        outbox.heard(at: now())
        let message = try desk.change(review) { [time = now(), session = outbox.session?.name] review throws(ReviewRefusal) in
            try review.reply(on: id, text: text, session: session, now: time)
        }
        notify(id, .message, message.text)
        return StateReport.Message(message, review: review, layout: layout)
    }

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

    func answered(_ id: ThreadID, with message: StateReport.Message) {
        guard let ask = asks[id] else { return }
        closeAsk(id, ask.ticket, .answered(message))
    }

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

    private func tookOver(from: String, to: ListenerSession, at time: Date) {
        takeover = Takeover(from: from, to: to.name, key: to.key, at: time)
        guard let general = review?.general.id else { return }
        announce?(Notice(thread: general, kind: .takeover, agent: to.name, text: "\(to.name) took over from \(from)", at: time))
    }

    private var review: Review? {
        desk.review(of: key)
    }

    private func deliver() {
        guard let waiting = open, let outcome = takeNext() else { return }
        open = nil
        waiting.timeout?.cancel()
        waiting.answer.resume(returning: outcome)
    }

    private func close(_ outcome: Outcome, where matches: (OpenWait) -> Bool) {
        guard let waiting = open, matches(waiting) else { return }
        open = nil
        waiting.timeout?.cancel()
        outbox.waitClosed(at: now())
        waiting.answer.resume(returning: outcome)
    }

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
