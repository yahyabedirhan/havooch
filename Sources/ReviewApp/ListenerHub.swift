import Foundation
import Observation
import ReviewCore
import ReviewStore

/// The listeners of one data folder: one `ListenerQueue`, with
/// its own outbox, per review (a plain video's or a project's), so two
/// agents can listen to two windows at the same time. A `wait` binds to
/// the review its caller names (the app resolves `--video` and
/// `--project`, or the key window's review); the listener's other commands
/// name an id, whose prefix names its review, so they find their queue
/// with no flag. A bare thread number in `reply` and `ask` is a thread of
/// the key window's review.
///
/// Queues are made the first time a review needs one and kept for the
/// run, so a listener of a video no window holds is still heard, and a
/// window that opens it later shows it.
@Observable
final class ListenerHub {
    /// The queues this run made, by review. A queue never changes for its
    /// review, and each queue is observed on its own, so the table isn't.
    @ObservationIgnored private var queues: [ReviewKey: ListenerQueue] = [:]
    /// Told each thing an agent says, and each takeover, with the review
    /// it's on, to show it as a notice in the window that holds the review.
    @ObservationIgnored var announce: (@MainActor (ReviewKey, Notice) -> Void)?
    /// The review a bare thread number (`reply 3`) is on: the key
    /// window's. The app sets it; nil with no video.
    @ObservationIgnored var keyReview: @MainActor () -> ReviewKey? = { nil }
    /// The project `slug` as `config.toml` lists it now, for each payload's
    /// project block. The app sets it.
    @ObservationIgnored var outline: @MainActor (String) -> ProjectOutline? = { _ in nil }
    /// Told each time an agent's `wait` opens on any review, with the review.
    @ObservationIgnored var connected: (@MainActor (ReviewKey) -> Void)?
    /// When this data opened: a listener the last run left reconnects for
    /// a while after it.
    let startedAt: Date
    @ObservationIgnored private let desk: ReviewDesk
    @ObservationIgnored private let layout: SupportLayout
    @ObservationIgnored private let now: @MainActor () -> Date

    /// The listeners of the reviews in `desk`'s library. The one outbox of
    /// builds before a listener per review is split into each review's
    /// first, once.
    init(desk: ReviewDesk, layout: SupportLayout, now: @escaping @MainActor () -> Date = { Date() }) {
        self.desk = desk
        self.layout = layout
        self.now = now
        startedAt = now()
        desk.library.migrateFormerOutbox()
    }

    /// The listener of the review `key`, made the first time it's asked
    /// for, from the outbox the last run left for it.
    func queue(for key: ReviewKey) -> ListenerQueue {
        if let queue = queues[key] { return queue }
        let queue = ListenerQueue(key: key, desk: desk, layout: layout, startedAt: startedAt, now: now)
        // The queue's own key: it changes when its review moves into a project.
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

    /// The listener of the review the thread, message or send `id` is on,
    /// by its prefix; nil when no review is that id's.
    func queue(of id: ItemID) -> ListenerQueue? {
        desk.key(of: id).map { queue(for: $0) }
    }

    /// The review `old` became the review `new` (`project new --from`):
    /// its listener, made now when the run had none, listens to `new`
    /// from now on, its `wait` still open (`ListenerQueue.rekey`).
    func rekey(_ old: ReviewKey, to new: ReviewKey) {
        let queue = queue(for: old)
        queues[old] = nil
        // A listener the run had for `new` already gives way: one per review.
        queues[new]?.stop()
        queue.rekey(to: new)
        queues[new] = queue
    }

    // MARK: - The listener's commands

    /// `havooch ack`, on the review the send's id names.
    func ack(_ sendID: String, text: String?) throws(AppRefusal) -> StateReport.Send {
        guard let id = ItemID(sendID), id.kind == .send, let queue = queue(of: id) else {
            throw AppRefusal("no send `\(sendID)`; the send `havooch wait` printed names its id")
        }
        return try queue.ack(sendID, text: text)
    }

    /// `havooch status`, on the review the message's id names.
    func status(_ messageID: String, _ state: MessageState, text: String? = nil) throws(AppRefusal) -> StateReport.Message {
        guard let id = ItemID(messageID), id.kind == .message, let queue = queue(of: id) else {
            throw AppRefusal("no message `\(messageID)`; the send `havooch wait` printed names each message's id")
        }
        return try queue.status(messageID, state, text: text)
    }

    /// `havooch reply`, on the review the thread's id names, or the key
    /// window's for a bare number.
    func reply(on thread: String, text: String) throws(AppRefusal) -> StateReport.Message {
        let (id, review) = try desk.threadID(thread, open: keyReview())
        return try queue(for: review).reply(on: id, of: review, text: text)
    }

    /// `havooch ask`, on the review the thread's id names, or the key
    /// window's for a bare number.
    func ask(
        on thread: String, question: String, choices: [String] = [], waitSeconds: Int?, connection: UUID? = nil
    ) async throws(AppRefusal) -> ListenerQueue.Asked {
        let (id, review) = try desk.threadID(thread, open: keyReview())
        return try await queue(for: review).ask(
            on: id, of: review, question: question, choices: choices, waitSeconds: waitSeconds, connection: connection
        )
    }

    // MARK: - Every listener

    /// Whether a listener has the send `id`, or is being handed it.
    func isDelivered(_ id: String) -> Bool {
        queues.values.contains { $0.isDelivered(id) }
    }

    /// The connection `connection` closed at its client's end: the `wait`
    /// or `ask` held on it, on whichever review, is over.
    func connectionClosed(_ connection: UUID) {
        for queue in queues.values { queue.connectionClosed(connection) }
    }

    /// The app quits, or leaves this data: every open `wait` and `ask` ends
    /// with no answer, so its command connects again.
    func stop() {
        for queue in queues.values { queue.stop() }
    }
}
