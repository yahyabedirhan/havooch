import Foundation
import Observation
import ReviewCore
import ReviewStore

@Observable
final class ListenerHub {
    @ObservationIgnored private var queues: [ReviewKey: ListenerQueue] = [:]
    @ObservationIgnored var announce: (@MainActor (ReviewKey, Notice) -> Void)?
    @ObservationIgnored var keyReview: @MainActor () -> ReviewKey? = { nil }
    @ObservationIgnored var outline: @MainActor (String) -> ProjectOutline? = { _ in nil }
    @ObservationIgnored var connected: (@MainActor (ReviewKey) -> Void)?
    let startedAt: Date
    @ObservationIgnored private let desk: ReviewDesk
    @ObservationIgnored private let layout: SupportLayout
    @ObservationIgnored private let now: @MainActor () -> Date

    init(desk: ReviewDesk, layout: SupportLayout, now: @escaping @MainActor () -> Date = { Date() }) {
        self.desk = desk
        self.layout = layout
        self.now = now
        startedAt = now()
        desk.library.migrateFormerOutbox()
    }

    func queue(for key: ReviewKey) -> ListenerQueue {
        if let queue = queues[key] { return queue }
        let queue = ListenerQueue(key: key, desk: desk, layout: layout, startedAt: startedAt, now: now)
        queue.announce = { [weak self, weak queue] notice in
            guard let queue else { return }
            self?.announce?(queue.key, notice)
        }
        queue.outline = { [weak self] slug in self?.outline(slug) }
        queue.connected = { [weak self, weak queue] in
            guard let queue else { return }
            self?.connected?(queue.key)
        }
        queues[key] = queue
        return queue
    }

    func queue(of id: ItemID) -> ListenerQueue? {
        desk.key(of: id).map { queue(for: $0) }
    }

    func rekey(_ old: ReviewKey, to new: ReviewKey) {
        let queue = queue(for: old)
        queues[old] = nil
        queues[new]?.stop()
        queue.rekey(to: new)
        queues[new] = queue
    }

    func ack(_ sendID: String, text: String?) throws(AppRefusal) -> StateReport.Send {
        guard let id = ItemID(sendID), id.kind == .send, let queue = queue(of: id) else {
            throw AppRefusal("no send `\(sendID)`; the send `havooch wait` printed names its id")
        }
        return try queue.ack(sendID, text: text)
    }

    func status(_ messageID: String, _ state: MessageState, text: String? = nil) throws(AppRefusal) -> StateReport.Message {
        guard let id = ItemID(messageID), id.kind == .message, let queue = queue(of: id) else {
            throw AppRefusal("no message `\(messageID)`; the send `havooch wait` printed names each message's id")
        }
        return try queue.status(messageID, state, text: text)
    }

    func reply(on thread: String, text: String) throws(AppRefusal) -> StateReport.Message {
        let (id, review) = try desk.threadID(thread, open: keyReview())
        return try queue(for: review).reply(on: id, of: review, text: text)
    }

    func ask(
        on thread: String, question: String, choices: [String] = [], waitSeconds: Int?, connection: UUID? = nil
    ) async throws(AppRefusal) -> ListenerQueue.Asked {
        let (id, review) = try desk.threadID(thread, open: keyReview())
        return try await queue(for: review).ask(
            on: id, of: review, question: question, choices: choices, waitSeconds: waitSeconds, connection: connection
        )
    }

    func isDelivered(_ id: String) -> Bool {
        queues.values.contains { $0.isDelivered(id) }
    }

    func connectionClosed(_ connection: UUID) {
        for queue in queues.values { queue.connectionClosed(connection) }
    }

    func stop() {
        for queue in queues.values { queue.stop() }
    }
}
