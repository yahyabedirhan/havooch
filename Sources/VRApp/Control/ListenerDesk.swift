import Foundation
import VRLease
import VRReview
import VRWire

/// The listener's requests. A `wait` gets the oldest batch waiting in the
/// outbox at once, or holds its connection open (parked) until the person
/// sends one or its time runs out. `ack`, `status` and `reply` are answered
/// at once; an `ask` holds its connection until the person answers. The
/// desk decides nothing by itself: the outbox says which batch goes to whom,
/// the review says what may be answered, and the model builds the payload.
@MainActor
final class ListenerDesk {
    private let model: ReviewModel
    /// Ends a `wait` or an `ask` once its time ran out.
    private let later: Later
    /// The `wait`s holding their connections open, oldest first.
    private var parked: [Parked] = []

    /// A parked `wait`: its connection's ticket, the listener session it
    /// came from and how it gets its answer.
    private struct Parked {
        var ticket: UUID
        var key: String
        var answer: CheckedContinuation<ControlServer.Answer, Never>
        /// Takes back the end of the wait at its time, once it's answered.
        var timeout: Later.Cancel?
    }

    /// The `ask`s holding their connections open, oldest first.
    private var asking: [Asking] = []

    /// A parked `ask`: its connection's ticket, the comment its question is
    /// on, how it wants its answer and how it gets it.
    private struct Asking {
        var ticket: UUID
        var commentID: String
        var json: Bool
        var answer: CheckedContinuation<ControlServer.Answer, Never>
        /// Takes back the end of the ask at its time, once it's answered.
        var timeout: Later.Cancel?
    }

    init(model: ReviewModel, later: Later = .sleeping) {
        self.model = model
        self.later = later
    }

    /// How many `wait`s hold their connections open.
    var waiting: Int { parked.count }
    /// How many `ask`s hold their connections open.
    var asks: Int { asking.count }

    /// `wait [--timeout <seconds>]` on the connection `ticket`. The listener
    /// is present from here until the wait closes. A wait from another
    /// session than the last listener's ends that one's parked waits: one
    /// listener at a time.
    func wait(by holder: Holder, timeout seconds: Int?, ticket: UUID) async -> ControlServer.Answer {
        // A batch the last run left goes out with its transcript.
        await model.restored()
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
                later.after(TimeInterval(seconds)) { [weak self] in self?.end(ticket, with: Self.ranOut(after: seconds)) }
            }
            parked.append(Parked(ticket: ticket, key: holder.key, answer: continuation, timeout: timeout))
        }
    }

    /// A batch was posted: the oldest parked `wait` gets it.
    func outboxChanged() {
        guard let first = parked.first, let answer = next(for: first.key) else { return }
        parked.removeFirst()
        first.timeout?()
        first.answer.resume(returning: answer)
    }

    /// The connection `ticket` went away while its `wait` or its `ask` was
    /// parked (its heartbeat couldn't be written): it closes. An ask's
    /// question stays open.
    func dropped(_ ticket: UUID) {
        let gone = ControlServer.Answer(reply: .refused("the listener went away"))
        end(ticket, with: gone)
        endAsk(ticket, with: gone)
    }

    /// A batch's answer was written to its `wait`, or couldn't be: the wait
    /// closes, and a batch that didn't arrive is pending again. An answer
    /// written to its `ask` isn't given again; one that couldn't be written
    /// waits for the next `ask`.
    func written(_ answer: ControlServer.Answer, delivered: Bool) {
        if let heard = answer.heard, delivered { model.answerHeard(heard) }
        guard let batch = answer.batch, let key = answer.listener else { return }
        if !delivered { model.parcelUndelivered(batch) }
        model.listenerLeft(key: key, delivered: delivered)
        // Another wait of the listener may be open for the batch that came back.
        if !delivered { outboxChanged() }
    }

    /// The app quits: every parked `wait` and `ask` hears why.
    func stop() {
        let quitting = ControlServer.Answer(reply: .refused("video-review is quitting"))
        for wait in parked { end(wait.ticket, with: quitting) }
        for ask in asking { endAsk(ask.ticket, with: quitting) }
    }

    // MARK: - Answering a batch

    /// `ack <batch-id> [<text>]`: `acknowledged b1`, or `{id}`.
    func acknowledge(_ batchID: String, text: String?, json: Bool) -> ControlReply {
        answer { () throws(ModelRefusal) in
            try model.acknowledge(batchID, text: text)
            return json ? JSONLine.string(Named(id: batchID)) : "acknowledged \(batchID)\n"
        }
    }

    /// `status <comment-id> working|done|failed`: `c1 is working`, or
    /// `{id, state}`.
    func setStatus(_ commentID: String, to name: String, json: Bool) -> ControlReply {
        answer { () throws(ModelRefusal) in
            guard let state = CommentState(rawValue: name) else {
                throw ModelRefusal("a comment's status is working, done or failed, not \(name)")
            }
            try model.setStatus(commentID, to: state)
            struct Status: Encodable { var id: String; var state: String }
            return json ? JSONLine.string(Status(id: commentID, state: name)) : "\(commentID) is \(name)\n"
        }
    }

    /// `reply <comment-id|batch-id> <text>`: `replied on c1`, or `{id}`.
    func reply(to id: String, text: String, json: Bool) -> ControlReply {
        answer { () throws(ModelRefusal) in
            try model.reply(to: id, text: text)
            return json ? JSONLine.string(Named(id: id)) : "replied on \(id)\n"
        }
    }

    /// `ask <comment-id> <question> [--wait <seconds>]` on the connection
    /// `ticket`: the question goes in the comment's thread, and the ask is
    /// held until the person answers or its time runs out. When the question
    /// is, in the same words, one whose answer no ask was given yet (the
    /// answer came after an earlier ask ran out), that answer comes back at
    /// once instead and nothing is asked. Another question is asked: an old
    /// answer never answers a new question (`ReviewSession.ask`).
    func ask(_ commentID: String, question: String, wait seconds: Int?, json: Bool, ticket: UUID) async -> ControlServer.Answer {
        let owed: ReviewSession.Exchange?
        do throws(ModelRefusal) {
            owed = try model.ask(commentID, question: question)
        } catch {
            return ControlServer.Answer(reply: .refused(error.reason))
        }
        if let owed { return Self.answer(owed, on: commentID, json: json) }
        guard seconds != 0 else { return Self.unanswered(after: 0) }
        return await withCheckedContinuation { continuation in
            let timeout = seconds.map { seconds in
                later.after(TimeInterval(seconds)) { [weak self] in self?.endAsk(ticket, with: Self.unanswered(after: seconds)) }
            }
            asking.append(Asking(ticket: ticket, commentID: commentID, json: json, answer: continuation, timeout: timeout))
        }
    }

    /// The question on the comment `commentID` was answered: every `ask`
    /// parked on it gets the answer.
    func answered(_ commentID: String) {
        guard let exchange = model.unheardAnswer(on: commentID) else { return }
        for ask in asking where ask.commentID == commentID {
            endAsk(ask.ticket, with: Self.answer(exchange, on: commentID, json: ask.json))
        }
    }

    /// An `ask`'s answer: the answer's text, or `{commentId, question,
    /// answer, answeredAt}`. Once it's written, the answer counts as heard.
    private static func answer(_ exchange: ReviewSession.Exchange, on commentID: String, json: Bool) -> ControlServer.Answer {
        struct Answered: Encodable { var commentId: String; var question: String; var answer: String; var answeredAt: String }
        let output = json
            ? JSONLine.string(Answered(
                commentId: commentID, question: exchange.question.text, answer: exchange.answer.text,
                answeredAt: exchange.answer.at.formatted(.iso8601)
            ))
            : exchange.answer.text + "\n"
        return ControlServer.Answer(reply: .done(output), heard: commentID)
    }

    /// An `ask` whose time ran out: done, with nothing to print and a note,
    /// which the command turns into exit 3. Its question stays open.
    private static func unanswered(after seconds: Int) -> ControlServer.Answer {
        ControlServer.Answer(reply: .done("", note: "no answer came within \(seconds) second\(seconds == 1 ? "" : "s")\n"))
    }

    /// Closes the parked `ask` on `ticket` with `answer`, when it's still
    /// parked.
    private func endAsk(_ ticket: UUID, with answer: ControlServer.Answer) {
        guard let index = asking.firstIndex(where: { $0.ticket == ticket }) else { return }
        let ask = asking.remove(at: index)
        ask.timeout?()
        ask.answer.resume(returning: answer)
    }

    /// `{id}`: what a change to one comment or batch prints with `--json`.
    private struct Named: Encodable {
        var id: String
    }

    /// The reply for what `body` prints, or for the model's refusal.
    private func answer(_ body: () throws(ModelRefusal) -> String) -> ControlReply {
        do throws(ModelRefusal) {
            return .done(try body())
        } catch {
            return .refused(error.reason)
        }
    }

    // MARK: - Delivering a batch

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
        wait.timeout?()
        model.listenerLeft(key: wait.key, delivered: false)
        wait.answer.resume(returning: answer)
    }

    /// A `wait` whose time ran out: done, with nothing to print and a note,
    /// which the command turns into exit 3.
    private static func ranOut(after seconds: Int) -> ControlServer.Answer {
        ControlServer.Answer(reply: .done("", note: "no batch came within \(seconds) second\(seconds == 1 ? "" : "s")\n"))
    }
}
