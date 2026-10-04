import Foundation
import VRLease
import VRWire

/// The listener's requests. A `wait` gets the oldest batch waiting in the
/// outbox at once, or holds its connection open (parked) until the person
/// sends one or its time runs out. The desk decides nothing by itself: the
/// outbox says which batch goes to whom, and the model builds the payload.
@MainActor
final class ListenerDesk {
    private let model: ReviewModel
    /// The `wait`s holding their connections open, oldest first.
    private var parked: [Parked] = []

    /// A parked `wait`: its connection's ticket, the listener session it
    /// came from and how it gets its answer.
    private struct Parked {
        var ticket: UUID
        var key: String
        var answer: CheckedContinuation<ControlServer.Answer, Never>
        /// Ends the wait when its time runs out; cancelled once it's answered.
        var timeout: Task<Void, Never>?
    }

    init(model: ReviewModel) {
        self.model = model
    }

    /// How many `wait`s hold their connections open.
    var waiting: Int { parked.count }

    /// `wait [--timeout <seconds>]` on the connection `ticket`. The listener
    /// is present from here until the wait closes. A wait from another
    /// session than the last listener's ends that one's parked waits: one
    /// listener at a time.
    func wait(by holder: Holder, timeout seconds: Int?, ticket: UUID) async -> ControlServer.Answer {
        for other in parked where other.key != holder.key {
            end(other.ticket, with: ControlServer.Answer(reply: .refused("another listener, \(holder.name), took over")))
        }
        model.listenerArrived(key: holder.key, name: holder.name)
        if let answer = next(for: holder.key) { return answer }
        guard seconds != 0 else {
            model.listenerLeft(key: holder.key, delivered: false)
            return Self.ranOut(after: 0)
        }
        return await withCheckedContinuation { continuation in
            let timeout = seconds.map { seconds in
                Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
                    self?.end(ticket, with: Self.ranOut(after: seconds))
                }
            }
            parked.append(Parked(ticket: ticket, key: holder.key, answer: continuation, timeout: timeout))
        }
    }

    /// A batch was posted: the oldest parked `wait` gets it.
    func outboxChanged() {
        guard let first = parked.first, let answer = next(for: first.key) else { return }
        parked.removeFirst()
        first.timeout?.cancel()
        first.answer.resume(returning: answer)
    }

    /// The connection `ticket` went away while its `wait` was parked (its
    /// heartbeat couldn't be written): the wait closes.
    func dropped(_ ticket: UUID) {
        end(ticket, with: ControlServer.Answer(reply: .refused("the listener went away")))
    }

    /// A batch's answer was written to its `wait`, or couldn't be: the wait
    /// closes, and a batch that didn't arrive is pending again.
    func written(_ answer: ControlServer.Answer, delivered: Bool) {
        guard let batch = answer.batch, let key = answer.listener else { return }
        if !delivered { model.parcelUndelivered(batch) }
        model.listenerLeft(key: key, delivered: delivered)
        // Another wait of the listener may be open for the batch that came back.
        if !delivered { outboxChanged() }
    }

    /// The app quits: every parked `wait` hears why.
    func stop() {
        for wait in parked {
            end(wait.ticket, with: ControlServer.Answer(reply: .refused("video-review is quitting")))
        }
    }

    /// The next batch for the listener `key` as its `wait`'s answer, or nil
    /// when none is pending.
    private func next(for key: String) -> ControlServer.Answer? {
        while let parcel = model.takeParcel() {
            do throws(ModelRefusal) {
                let payload = try model.payload(for: parcel)
                return ControlServer.Answer(reply: .done(JSONLine.string(payload)), batch: parcel.batchID, listener: key)
            } catch {
                // A batch the app has no review of can't be delivered to anyone.
                model.parcelDropped(parcel.batchID)
            }
        }
        return nil
    }

    /// Closes the parked `wait` on `ticket` with `answer`, when it's still
    /// parked.
    private func end(_ ticket: UUID, with answer: ControlServer.Answer) {
        guard let index = parked.firstIndex(where: { $0.ticket == ticket }) else { return }
        let wait = parked.remove(at: index)
        wait.timeout?.cancel()
        model.listenerLeft(key: wait.key, delivered: false)
        wait.answer.resume(returning: answer)
    }

    /// A `wait` whose time ran out: done, with nothing to print and a note,
    /// which the command turns into exit 3.
    private static func ranOut(after seconds: Int) -> ControlServer.Answer {
        ControlServer.Answer(reply: .done("", note: "no batch came within \(seconds) second\(seconds == 1 ? "" : "s")\n"))
    }
}
