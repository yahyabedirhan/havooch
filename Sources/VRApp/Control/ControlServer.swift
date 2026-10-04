import Foundation
import VRLease
import VRReview
import VRWire

/// App control's server: while the app runs it listens on the control
/// socket and answers one JSON request per connection with one reply. Each
/// request is decoded, version-checked and leased before it reaches
/// `AppModel`, then answered on the main actor. Every refusal is a reply,
/// so the `video-review` command always has a line to print. A `take`'s
/// reply granting the lease that can't be written (its client gone) gives
/// the lease up at once, and a `wait`'s reply carrying a batch that can't
/// be written leaves the batch for the next `wait`.
@MainActor
final class ControlServer {
    /// A reply, whether the app quits once it's written, and what the
    /// reply hands over: the lease a `control take`'s reply grants,
    /// released when the reply can't be written (`undelivered`), and the
    /// batch a `wait`'s reply carries, taken once the reply is written
    /// (`written`) and still pending when it can't be.
    struct Answer: Equatable, Sendable {
        var reply: ControlReply
        var quits = false
        var granted: ControlLease.Term?
        var delivery: ListenerQueue.Handed?

        /// Whether the server must hear how writing the reply went.
        var handsOver: Bool { granted != nil || delivery != nil }
    }

    let socket: URL
    private let model: AppModel
    private let screenshotter: Screenshotter
    private let quit: @MainActor @Sendable () -> Void
    /// The time the lease is decided at, and the zone its refusals name it in.
    private let now: @MainActor () -> Date
    private let timeZone: TimeZone
    /// App control's lease: who may send operator requests, and until when.
    /// Each change is shown (`indicator`) and its end looked out for.
    private(set) var lease: ControlLease {
        didSet { leaseChanged() }
    }
    /// The banner, which follows the lease.
    let indicator: LeaseIndicator
    /// Ends the lease once it runs out, when no request comes to.
    private var settling: Task<Void, Never>?
    /// The `take`s waiting in line, each holding its connection open until
    /// it gets the lease or its wait runs out.
    private var waiters: [UUID: Waiter] = [:]
    private var listener: SocketListener?
    /// How often a connection that waits for its answer is written to.
    private let heartbeat: Duration

    /// A `take` waiting in line: who sent it, how long it waits, and how it
    /// gets its answer.
    private struct Waiter {
        var holder: Holder
        var seconds: Int
        var json: Bool
        var answer: CheckedContinuation<Answer, Never>
        /// Ends the wait when it runs out; cancelled once it's answered.
        var timeout: Task<Void, Never>
    }

    init(
        socket: URL,
        model: AppModel,
        screenshotter: Screenshotter,
        lease: ControlLease = ControlLease(),
        indicator: LeaseIndicator,
        now: @escaping @MainActor () -> Date = { Date() },
        timeZone: TimeZone = .current,
        heartbeat: Duration = SocketListener.heartbeat,
        quit: @escaping @MainActor @Sendable () -> Void
    ) {
        self.socket = socket
        self.model = model
        self.screenshotter = screenshotter
        self.lease = lease
        self.indicator = indicator
        self.now = now
        self.timeZone = timeZone
        self.heartbeat = heartbeat
        self.quit = quit
        // The banner's Stop is the person's only way into the lease.
        indicator.stop = { [weak self] in self?.stopLease() }
        // `didSet` doesn't run in `init`: a lease a relaunch handed over is
        // shown, and its end looked out for, from the start.
        leaseChanged()
    }

    // MARK: - Dispatch

    /// The answer to one request as the client sent it. An operator's
    /// request asks the lease first, and is refused with nothing done when
    /// the lease says no. A quit hands the lease back in its reply, for a
    /// relaunch to pass on. A `take` that waits in line is answered once it
    /// gets the lease or its wait runs out, other requests answered
    /// meanwhile.
    func reply(to data: Data) async -> Answer {
        let message: ControlMessage
        do throws(ControlProtocolError) {
            message = try ControlMessage.decode(data)
        } catch {
            return Answer(reply: .refused(error.message))
        }
        var renewed: ControlLease.Term?
        if message.request.isLeased {
            let time = now()
            switch lease.use(by: message.holder, at: time).answer {
            case .success(let term): renewed = term
            case .failure(let refusal): return Answer(reply: .refused(refusal.message(at: time, timeZone: timeZone)))
            }
        }
        let json = message.json
        do throws(ActionError) {
            switch message.request {
            case .appStatus, .appOpen:
                let status = await snapshot().status
                return done(json ? status.json : status.text)
            case .state:
                return done(await snapshot().json)
            case .controlTake(let seconds):
                return await take(by: message.holder, waiting: seconds, json: json)
            case .controlRelease:
                // The next waiter's take is answered as the lease changes (`leaseChanged`).
                _ = lease.release(by: message.holder, at: now())
                return done(json ? "{\"released\":true}\n" : "released\n")
            case .appQuit:
                // An open `wait` hears why while the app can still write to it.
                model.listener.quitting()
                return Answer(reply: ControlReply(ok: true, output: json ? "{\"quit\":true}\n" : "quit\n", lease: renewed), quits: true)
            case .playerOpen(let path):
                struct Opened: Encodable {
                    @Nulled var video: StateSnapshot.Video?
                }
                let video = try await model.open(URL(fileURLWithPath: path))
                return done(json ? JSONText.line(Opened(video: await snapshot().video)) : video.path + "\n")
            case .playerPlay:
                try model.play()
                return playhead(json)
            case .playerPause:
                try model.pause()
                return playhead(json)
            case .playerSeek(let seconds):
                try await model.seek(to: seconds)
                return playhead(json)
            case .screenshot(let path, let appearance):
                return await screenshot(to: path, appearance: appearance, json: json)
            case .commentAdd(let text, let at, let region):
                return comment(try await model.addComment(text: text, at: at, region: try Self.checked(region)), json)
            case .commentEdit(let id, let text):
                return comment(try model.editComment(CommentID(rawValue: id), text: text), json)
            case .commentDelete(let id):
                struct Deleted: Encodable {
                    var deleted: String
                }
                try model.deleteComment(CommentID(rawValue: id))
                return done(json ? JSONText.line(Deleted(deleted: id)) : "deleted \(id)\n")
            case .batchSend:
                struct Sent: Encodable {
                    var batchId: String
                    var commentIds: [String]
                }
                let batch = try await model.sendBatch()
                return done(
                    json ? JSONText.line(Sent(batchId: batch.id.rawValue, commentIds: batch.comments.map(\.rawValue)))
                        : batch.id.rawValue + "\n"
                )
            case .wait(let timeout):
                switch await model.listener.wait(holder: message.holder, timeout: timeout) {
                case .batch(let handed, let payload): return Answer(reply: .done(payload), delivery: handed)
                // Nothing to print: the command, which knows it waited, exits 3.
                case .timedOut: return done("")
                case .refused(let why): return Answer(reply: .refused(why))
                case .gone: return Answer(reply: .refused("the listener's connection closed"))
                }
            case .contextSet(let text):
                struct Noted: Encodable {
                    var note: String
                }
                let note = try model.setNote(text)
                return done(json ? JSONText.line(Noted(note: note)) : "context note set\n")
            case .ack(let id, let text):
                struct Acknowledged: Encodable {
                    var batchId: String
                    var commentIds: [String]
                }
                let batch = try model.listener.acknowledge(id, text: text, holder: message.holder)
                return done(
                    json ? JSONText.line(Acknowledged(batchId: batch.id.rawValue, commentIds: batch.comments.map(\.rawValue)))
                        : "acknowledged \(batch.id.rawValue)\n"
                )
            case .status(let id, let state):
                let changed = try model.listener.setStatus(id, state, holder: message.holder)
                return done(json ? JSONText.line(model.shown(changed)) : "\(changed.id.rawValue) \(changed.state.rawValue)\n")
            case .reply(let id, let text):
                struct Replied: Encodable {
                    var batchId: String
                }
                switch try model.listener.reply(id, text: text, holder: message.holder) {
                case .comment(let comment):
                    return done(json ? JSONText.line(model.shown(comment)) : "replied \(comment.id.rawValue)\n")
                case .batch(let batch):
                    return done(json ? JSONText.line(Replied(batchId: batch.id.rawValue)) : "replied \(batch.id.rawValue)\n")
                }
            case .ask(let id, let question, let wait):
                struct Answered: Encodable {
                    var commentId: String
                    var answer: String
                }
                switch await model.listener.ask(id, question: question, wait: wait, holder: message.holder) {
                case .answer(let answer): return done(json ? JSONText.line(Answered(commentId: id, answer: answer)) : answer + "\n")
                // Nothing to print: the command, which knows it waited, exits 3.
                case .timedOut: return done("")
                case .refused(let why): return Answer(reply: .refused(why))
                case .gone: return Answer(reply: .refused("the listener's connection closed"))
                }
            case .threadAnswer(let id, let text):
                let answered = try model.answer(CommentID(rawValue: id), text: text)
                return done(json ? JSONText.line(model.shown(answered)) : "answered \(answered.id.rawValue)\n")
            }
        } catch {
            return Answer(reply: .refused(error.message))
        }
    }

    /// `region` as the review keeps it, or the review's refusal: the wire
    /// carries any four numbers.
    private static func checked(_ region: WireRegion?) throws(ActionError) -> Region? {
        guard let region else { return nil }
        do throws(ReviewError) {
            return try Region.checked(x: region.x, y: region.y, w: region.w, h: region.h)
        } catch {
            throw .review(error)
        }
    }

    /// What the window shows, with the transcript and the lease as they
    /// are now.
    private func snapshot() async -> StateSnapshot {
        let transcript = await model.transcriptStatus()
        return model.snapshot(lease: lease.status(at: now()), transcript: transcript)
    }

    private func done(_ output: String) -> Answer {
        Answer(reply: .done(output))
    }

    /// What `player play`, `pause` and `seek` print: where the playhead is.
    private func playhead(_ json: Bool) -> Answer {
        struct Playhead: Encodable {
            var time: Double
            var playing: Bool
        }
        let player = model.player
        return done(json ? JSONText.line(Playhead(time: player.time, playing: player.playing)) : TimeText.precise(player.time) + "\n")
    }

    /// What `comment add` and `comment edit` print: the comment's id, or
    /// the comment as `state` shows it.
    private func comment(_ comment: Comment, _ json: Bool) -> Answer {
        done(json ? JSONText.line(model.shown(comment)) : comment.id.rawValue + "\n")
    }

    private func screenshot(to path: String, appearance: ControlRequest.Appearance?, json: Bool) async -> Answer {
        struct Shot: Encodable {
            var path: String
            var captured: Bool
        }
        let rendered: String?
        switch await screenshotter.capture(to: URL(fileURLWithPath: path), appearance: appearance) {
        case .captured: rendered = nil
        case .rendered(let why): rendered = why
        case .failed(let why): return Answer(reply: .refused(why))
        }
        return Answer(reply: .done(
            json ? JSONText.line(Shot(path: path, captured: rendered == nil)) : path + "\n",
            note: rendered.map { "the window was rendered, not captured: \($0)\n" } ?? ""
        ))
    }

    // MARK: - Taking turns

    /// `control take`: held to the cap at once when the lease is the
    /// holder's or free. While another holds it, refused at once without a
    /// wait; with one, the take waits in line, suspended so the main actor
    /// answers other requests (the holder's release among them), until
    /// `leaseChanged` finds the lease handed to it or its wait runs out.
    private func take(by holder: Holder, waiting seconds: Int?, json: Bool) async -> Answer {
        let time = now()
        // Without a wait the deadline is now, which never queues.
        let seconds = seconds ?? 0
        let deadline = time.addingTimeInterval(TimeInterval(seconds))
        switch lease.take(by: holder, at: time, waitingUntil: deadline).answer {
        case .success(let term):
            return held(term, json: json)
        case .failure(.queued):
            break
        case .failure(let refusal):
            return Answer(reply: .refused(refusal.message(at: time, timeZone: timeZone)))
        }
        let ticket = UUID()
        return await withCheckedContinuation { continuation in
            let timeout = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
                self?.waitRanOut(ticket, deadline: deadline)
            }
            waiters[ticket] = Waiter(holder: holder, seconds: seconds, json: json, answer: continuation, timeout: timeout)
        }
    }

    /// A waiting `take`'s wait ran out (unless it was answered already): it
    /// leaves the line, refused with who still holds the lease, or holding
    /// it should it be free by now.
    private func waitRanOut(_ ticket: UUID, deadline: Date) {
        guard let waiter = waiters.removeValue(forKey: ticket) else { return }
        // Never before the deadline the take was given, whatever the clock says.
        let time = max(now(), deadline)
        switch lease.giveUp(by: waiter.holder, waited: waiter.seconds, at: time).answer {
        case .success(let term):
            waiter.answer.resume(returning: held(term, json: waiter.json))
        case .failure(let refusal):
            waiter.answer.resume(returning: Answer(reply: .refused(refusal.message(at: time, timeZone: timeZone))))
        }
    }

    /// A `take`'s answer holding the lease to `term`'s end, which it grants.
    private func held(_ term: ControlLease.Term, json: Bool) -> Answer {
        let time = now()
        let status = ControlLease.Status(
            holder: term.holder.name, place: term.holder.place, secondsLeft: term.secondsLeft(at: time), waiting: lease.waiting(at: time)
        )
        return Answer(reply: .done(json ? JSONText.line(status) : term.held(timeZone: timeZone) + "\n"), granted: term)
    }

    /// A `take`'s reply that granted the lease couldn't be written: its
    /// client has gone (stopped, or cut off by its harness's timeout while
    /// it waited in line), so nobody knows they hold it. The lease is given
    /// up for that holder at once, and the next waiter gets it as usual,
    /// rather than it sitting unused until it runs out. A lease that has
    /// moved on meanwhile (another holder's, or a new one) is left alone.
    func undelivered(_ answer: Answer) {
        // A batch whose `wait` has gone is still pending, for the next one.
        if let delivery = answer.delivery { model.listener.undelivered(delivery) }
        guard let granted = answer.granted, let term = lease.current(at: now()),
              term.holder.key == granted.holder.key, term.taken == granted.taken else { return }
        _ = lease.release(by: granted.holder, at: now())
    }

    /// An answer that hands something over was written to its client: the
    /// batch a `wait` got is now taken by its listener.
    func written(_ answer: Answer) {
        if let delivery = answer.delivery { model.listener.delivered(delivery) }
    }

    // MARK: - The person taking the app back

    /// The banner's Stop: the holder's lease ends and it's barred for five
    /// minutes (`ControlLease.stop`), and the first waiter in line gets the
    /// lease, its `take` answered as the lease changes.
    func stopLease() {
        _ = lease.stop(at: now())
    }

    // MARK: - The lease's end

    /// Ends the lease if it has run out by now, handing it to the first
    /// waiter in line. A timer calls it at the lease's end, so the banner
    /// goes, and the waiter gets the lease, with no request.
    func settleLease() {
        _ = lease.settle(at: now())
    }

    /// The one place a change to the lease is applied: it's shown as it is
    /// now, a holder that got it from the line has its waiting `take`s
    /// answered, and its end is looked out for, the timer set for the last
    /// change replaced by one for this one.
    private func leaseChanged() {
        if indicator.lease != lease { indicator.lease = lease }
        settling?.cancel()
        settling = nil
        let time = now()
        if let term = lease.current(at: time) {
            for (ticket, waiter) in waiters where waiter.holder.key == term.holder.key {
                waiters[ticket] = nil
                waiter.timeout.cancel()
                waiter.answer.resume(returning: held(term, json: waiter.json))
            }
        }
        guard let end = lease.nextEnd(after: time) else { return }
        let left = end.timeIntervalSince(time)
        settling = Task { [weak self] in
            // A wake before the end settles nothing, and sets the timer again.
            try? await Task.sleep(for: .seconds(left))
            guard !Task.isCancelled else { return }
            self?.settleLease()
        }
    }

    // MARK: - Listening

    /// Starts listening on the socket.
    func start() throws(SocketListener.Failure) {
        guard listener == nil else { return }
        listener = try SocketListener.open(at: socket, heartbeat: heartbeat) { [weak self] data in
            await self?.reply(to: data) ?? Answer(reply: .refused("video-review is quitting"))
        } written: { [weak self] answer in
            self?.written(answer)
        } undelivered: { [weak self] answer in
            self?.undelivered(answer)
        } quit: { [quit] in
            quit()
        }
    }

    /// Stops listening and removes the socket, so the `video-review`
    /// command finds the app gone.
    func stop() {
        listener?.close()
        listener = nil
        settling?.cancel()
        settling = nil
        // A take waiting in line hears why, rather than a dropped connection.
        for waiter in waiters.values {
            waiter.timeout.cancel()
            waiter.answer.resume(returning: Answer(reply: .refused("video-review is quitting")))
        }
        waiters = [:]
        model.listener.quitting()
    }
}
