import Foundation
import ReviewCore
import ReviewLease
import ReviewWire

/// Why the app refuses an action, as the one line the command prints.
nonisolated struct AppRefusal: Error, Equatable {
    var reason: String

    init(_ reason: String) {
        self.reason = reason
    }
}

/// The app as the control server drives it: the actions an operator can
/// take. `AppModel` is the real one; the server's tests use a fake.
protocol AppControlling: AnyObject {
    func state() -> StateReport
    func open(_ url: URL) async throws(AppRefusal)
    func play() throws(AppRefusal)
    func pause() throws(AppRefusal)
    func seek(to seconds: Double) async throws(AppRefusal)
    /// Queues a comment at `at`, or at the player's time, on `region` of
    /// the frame when it has one, once its keyframe and its crop are on
    /// disk.
    func addComment(text: String, at: Double?, region: Region?) async throws(AppRefusal) -> StateReport.Comment
    func editComment(_ id: String, text: String) throws(AppRefusal) -> StateReport.Comment
    func deleteComment(_ id: String) throws(AppRefusal) -> StateReport.Comment
    /// Sets the open video's context note, without the space around it,
    /// and returns it as it's kept. An empty text clears the note.
    func setContextNote(_ text: String) throws(AppRefusal) -> String
    /// Sends every queued comment as one batch, and hands it to the
    /// listener queue.
    func sendBatch() async throws(AppRefusal) -> StateReport.Batch
    /// Answers the open question of a comment, as the answer box does.
    func answer(_ commentID: String, text: String) throws(AppRefusal) -> StateReport.Comment
}

/// App control's server: it decodes each request, checks the lease and
/// dispatches it, one JSON request per connection with one reply. The
/// socket, each connection and the heartbeat are `SocketListener`'s, which
/// reads each request off the main actor and hands it here
/// (`reply(to:)`). Every refusal is a reply, so the `video-review`
/// command always has a line to print. The server owns the one lease: an
/// operator request asks it first, and a `take`'s reply granting it that
/// can't be written (its client gone) gives it up at once. A listener's
/// requests go to the `ListenerQueue`, with no lease: a `wait` and an `ask`
/// are held like a `take` in line, and a batch whose reply can't be written
/// goes back to the front of the listener's line.
final class ControlServer {
    /// A reply, whether the app quits once it's written, and what only the
    /// client would know, undone when the reply can't be written
    /// (`undelivered`): the lease a `control take`'s reply grants, and the
    /// batch a `wait`'s reply carries.
    nonisolated struct Answer: Equatable {
        var reply: ControlReply
        var quits = false
        var granted: LeaseTerm?
        var delivered: BatchRef?
        /// Nothing is written: the connection just closes, as it does when
        /// the app isn't there, so a `wait` connects again.
        var silent = false
    }

    let socket: URL
    private let app: any AppControlling
    /// The listener's side: the open `wait` and the batches in line.
    private let listeners: ListenerQueue
    private let screenshotter: any Screenshotting
    private let quit: @MainActor () -> Void
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

    /// A `take` waiting in line: who sent it, how long it waits, and how it
    /// gets its answer.
    private struct Waiter {
        var holder: Holder
        var seconds: Int
        var json: Bool
        var answer: CheckedContinuation<Answer, Never>
        /// Ends the wait when it runs out; cancelled once it's answered.
        var timeout: Task<Void, Never>?
    }

    /// What the app does at launch before it answers its first request:
    /// opening the last video again. Nil when there's nothing to wait for.
    var ready: Task<Void, Never>?

    init(
        socket: URL,
        app: any AppControlling,
        listeners: ListenerQueue,
        screenshotter: any Screenshotting,
        lease: ControlLease = ControlLease(),
        indicator: LeaseIndicator = LeaseIndicator(),
        now: @escaping @MainActor () -> Date = { Date() },
        timeZone: TimeZone = .current,
        quit: @escaping @MainActor () -> Void
    ) {
        self.socket = socket
        self.app = app
        self.listeners = listeners
        self.screenshotter = screenshotter
        self.lease = lease
        self.indicator = indicator
        self.now = now
        self.timeZone = timeZone
        self.quit = quit
        // `didSet` doesn't run in `init`: a lease a relaunch handed over is
        // shown, and its end looked out for, from the start.
        leaseChanged()
    }

    // MARK: - Dispatch

    /// The answer to one request as the client sent it. A request that
    /// doesn't read, or speaks another version, is refused before anything
    /// is done. An operator request asks the lease first: refused for
    /// anyone but its holder, with nothing done. A quit hands the lease
    /// back in its reply, for a relaunch to pass on. A `take` that waits in
    /// line is answered once it gets the lease or its wait runs out, other
    /// requests answered meanwhile; so is a listener's `wait`, once a batch
    /// is sent. `connection` names the connection the request came over,
    /// so a held `wait` ends when its client goes away (`connectionClosed`).
    func reply(to data: Data, connection: UUID? = nil) async -> Answer {
        // The app is still opening its last video: a command sees the app
        // with it open, not the moment before.
        await ready?.value
        let message: ControlMessage
        do throws(ControlProtocolError) {
            message = try ControlMessage.decode(data)
        } catch {
            return Answer(reply: .refused(error.message))
        }
        let json = message.json
        var held: LeaseTerm?
        if message.request.role == .operator {
            let time = now()
            switch lease.use(by: message.holder, at: time).answer {
            case .success(let term): held = term
            case .failure(let refusal): return Answer(reply: .refused(refusal.message(at: time, timeZone: timeZone)))
            }
        }
        do throws(AppRefusal) {
            switch message.request {
            case .controlTake(let seconds):
                return await take(by: message.holder, waiting: seconds, json: json)
            case .controlRelease:
                // The next waiter's take is answered as the lease changes (`leaseChanged`).
                _ = lease.release(by: message.holder, at: now())
                return done("released \(AppIdentity.appName)", Output(released: true), json)
            case .appStatus, .appOpen:
                let state = state()
                return done(json ? state.statusJSON : state.statusLines)
            case .state:
                let state = state()
                return done(json ? state.json : state.lines)
            case .appQuit:
                let line = "\(AppIdentity.appName) quit"
                let output = json ? StateReport.json(Output(quit: true)) : line + "\n"
                return Answer(reply: ControlReply(ok: true, output: output, lease: held), quits: true)
            case .playerOpen(let path):
                try await app.open(URL(fileURLWithPath: path))
                let state = app.state()
                let line = state.video.map { "opened \($0.title) (\(TimeCode.text($0.duration)))" } ?? "opened \(path)"
                return done(line, Output(video: state.video, player: state.player), json)
            case .playerPlay:
                try app.play()
                let player = app.state().player
                return done("playing from \(TimeCode.text(player.time))", Output(player: player), json)
            case .playerPause:
                try app.pause()
                let player = app.state().player
                return done("paused at \(TimeCode.text(player.time))", Output(player: player), json)
            case .playerSeek(let seconds):
                try await app.seek(to: seconds)
                let player = app.state().player
                return done(TimeCode.text(player.time), Output(player: player), json)
            case .screenshot(let path, let appearance, let hideAgentIndicator):
                try await screenshotter.capture(to: URL(fileURLWithPath: path), appearance: appearance, hideAgentIndicator: hideAgentIndicator)
                return done(path, Output(path: path), json)
            case .commentAdd(let text, let at, let rectangle):
                // Numbers that aren't a region of the frame are refused
                // before the app is asked for anything.
                var region: Region?
                if let rectangle {
                    do throws(ReviewRefusal) {
                        region = try Region(x: rectangle.x, y: rectangle.y, w: rectangle.w, h: rectangle.h)
                    } catch {
                        throw AppRefusal(error.line)
                    }
                }
                let comment = try await app.addComment(text: text, at: at, region: region)
                let place = comment.region.map { " on the region \($0.text)" } ?? ""
                return done("\(comment.id) queued at \(TimeCode.text(comment.time))\(place)", Output(comment: comment), json)
            case .commentEdit(let id, let text):
                let comment = try app.editComment(id, text: text)
                return done("\(comment.id) edited", Output(comment: comment), json)
            case .commentDelete(let id):
                let comment = try app.deleteComment(id)
                return done("\(comment.id) deleted", Output(deleted: comment.id), json)
            case .contextSet(let text):
                let note = try app.setContextNote(text)
                let line = note.isEmpty
                    ? "context note cleared"
                    : "context note set (\(note.count) character\(note.count == 1 ? "" : "s"))"
                return done(line, Output(video: app.state().video), json)
            case .batchSend:
                let batch = try await app.sendBatch()
                let count = batch.commentIds.count
                let taken = listeners.outbox.taken.contains { $0.batchID.text == batch.id }
                let line = "\(batch.id) sent with \(count) comment\(count == 1 ? "" : "s"), "
                    + (taken ? "taken by the listener" : "waiting for a listener")
                return done(line, Output(batch: batch), json)
            case .wait(let timeout):
                switch await listeners.wait(by: message.holder, timeout: timeout, connection: connection) {
                case .batch(let ref, let payload):
                    return Answer(reply: .done(payload), delivered: ref)
                case .ranOut:
                    return Answer(reply: .ranOut)
                case .replaced:
                    return Answer(reply: .refused("a newer `video-review wait` took this one's place: one listener at a time"))
                case .gone:
                    return Answer(reply: .refused("\(AppIdentity.appName) is quitting"), silent: true)
                }
            case .ack(let batchID, let text):
                let batch = try listeners.ack(batchID, text: text)
                let count = batch.commentIds.count
                return done("\(batch.id) acknowledged, \(count) comment\(count == 1 ? "" : "s")", Output(batch: batch), json)
            case .status(let commentID, let status):
                // Every status is a comment state of the same name.
                let state = CommentState(rawValue: status.rawValue) ?? .working
                let comment = try listeners.status(commentID, state)
                return done("\(comment.id) \(comment.state)", Output(comment: comment), json)
            case .reply(let id, let text):
                let message = try listeners.reply(to: id, text: text)
                return done("\(message.id) on \(id)", Output(message: message), json)
            case .ask(let commentID, let question, let waitSeconds):
                switch try await listeners.ask(commentID, question: question, waitSeconds: waitSeconds, connection: connection) {
                case .answered(let answer):
                    return done(answer.text, Output(answer: answer), json)
                case .ranOut:
                    return Answer(reply: .ranOut)
                case .gone:
                    return Answer(reply: .refused("\(AppIdentity.appName) is quitting"), silent: true)
                }
            case .threadAnswer(let commentID, let text):
                let comment = try app.answer(commentID, text: text)
                return done("\(comment.id) answered", Output(comment: comment), json)
            }
        } catch {
            return Answer(reply: .refused(error.reason))
        }
    }

    /// What an action prints with `--json`: only the parts it changed.
    private struct Output: Encodable {
        var video: StateReport.Video?
        var player: StateReport.Player?
        var path: String?
        var quit: Bool?
        var lease: ControlLease.Status?
        var released: Bool?
        var comment: StateReport.Comment?
        var deleted: String?
        var batch: StateReport.Batch?
        var message: StateReport.Message?
        var answer: StateReport.Message?
    }

    /// What the app shows, with the lease and the listener as they are now.
    private func state() -> StateReport {
        var state = app.state()
        state.lease = lease.status(at: now())
        state.listener = listeners.report(at: now())
        return state
    }

    private func done(_ output: String) -> Answer {
        Answer(reply: .done(output))
    }

    /// Done: `line`, or `output` as JSON when the caller passed `--json`.
    private func done(_ line: String, _ output: Output, _ json: Bool) -> Answer {
        Answer(reply: .done(json ? StateReport.json(output) : line + "\n"))
    }

    // MARK: - Taking turns

    /// `control take`: held to the cap at once when the lease is the
    /// holder's or free. While another holds it, refused at once without a
    /// wait; with one, the take waits in line, suspended so the main actor
    /// answers other requests (the holder's release among them), until
    /// `leaseChanged` finds the lease handed to it or its wait runs out.
    private func take(by holder: Holder, waiting seconds: Int?, json: Bool) async -> Answer {
        let time = now()
        let decision = lease.take(by: holder, at: time, waitingUntil: seconds.map { time.addingTimeInterval(TimeInterval($0)) })
        switch decision.answer {
        case .success(let term):
            return granting(term, json: json)
        case .failure(.queued):
            break
        case .failure(let refusal):
            return Answer(reply: .refused(refusal.message(at: time, timeZone: timeZone)))
        }
        // Queued only with a wait after now.
        let seconds = seconds ?? 0
        let deadline = time.addingTimeInterval(TimeInterval(seconds))
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
            waiter.answer.resume(returning: granting(term, json: waiter.json))
        case .failure(let refusal):
            waiter.answer.resume(returning: Answer(reply: .refused(refusal.message(at: time, timeZone: timeZone))))
        }
    }

    /// A `take`'s answer holding the lease to `term`'s end, which it grants.
    private func granting(_ term: LeaseTerm, json: Bool) -> Answer {
        var answer = done(term.held(timeZone: timeZone), Output(lease: lease.status(at: now())), json)
        answer.granted = term
        return answer
    }

    /// A `take`'s reply that granted the lease couldn't be written: its
    /// client has gone (stopped, or cut off by its harness's timeout while
    /// it waited in line), so nobody knows they hold it. The lease is given
    /// up for that holder at once, and the next waiter gets it as usual,
    /// rather than it sitting unused until it runs out. A lease that has
    /// moved on meanwhile (another holder's, or a new one) is left alone.
    /// A `wait`'s reply that carried a batch and couldn't be written: the
    /// listener never got the batch, so it's first in its line again.
    func undelivered(_ answer: Answer) {
        if let ref = answer.delivered { listeners.undelivered(ref) }
        guard let granted = answer.granted, let term = lease.current(at: now()),
              term.holder.key == granted.holder.key, term.taken == granted.taken else { return }
        _ = lease.release(by: granted.holder, at: now())
    }

    /// The client of `connection` closed its socket while its request was
    /// held: a `wait` or an `ask` on it is over.
    func connectionClosed(_ connection: UUID) {
        listeners.connectionClosed(connection)
    }

    // MARK: - The person taking the app back

    /// The banner's Stop: the holder's lease ends and it's barred for five
    /// minutes (`ControlLease.stop`), and the first waiter in line gets the
    /// lease, its `take` answered as the lease changes. The person's only
    /// way into the lease.
    func stopLease() {
        _ = lease.stop(at: now())
    }

    // MARK: - The lease's end

    /// Ends the lease if it has run out by now, handing it to the first
    /// waiter in line, and lifts the bars that have ended. A timer calls it
    /// at the next of those ends, so the banner goes, and the waiter gets
    /// the lease, with no request.
    func settleLease() {
        _ = lease.settle(at: now())
    }

    /// The one place a change to the lease is applied: it's shown as it is
    /// now, a holder that got it from the line has its waiting `take`s
    /// answered, and its next end (the lease's or a bar's) is looked out
    /// for, the timer set for the last change replaced by one for this one.
    private func leaseChanged() {
        if indicator.lease != lease { indicator.lease = lease }
        settling?.cancel()
        settling = nil
        let time = now()
        if let term = lease.current(at: time) {
            for (ticket, waiter) in waiters where waiter.holder.key == term.holder.key {
                waiters[ticket] = nil
                waiter.timeout?.cancel()
                waiter.answer.resume(returning: granting(term, json: waiter.json))
            }
        }
        guard let next = lease.nextEnd(after: time) else { return }
        let left = next.timeIntervalSince(time)
        settling = Task { [weak self] in
            // A wake before the end settles nothing, and sets the timer again.
            try? await Task.sleep(for: .seconds(left))
            guard !Task.isCancelled else { return }
            self?.settleLease()
        }
    }

    // MARK: - Listening

    /// Starts listening on `socket` (`SocketListener.open`), with a
    /// heartbeat every `heartbeat` on each held connection.
    func start(heartbeat: Duration = SocketListener.heartbeat) throws(SocketListener.Failure) {
        guard listener == nil else { return }
        listener = try SocketListener.open(at: socket, heartbeat: heartbeat) { [weak self] data, connection in
            await self?.reply(to: data, connection: connection) ?? Answer(reply: .refused("\(AppIdentity.appName) is quitting"))
        } undelivered: { [weak self] answer in
            self?.undelivered(answer)
        } hungUp: { [weak self] connection in
            self?.connectionClosed(connection)
        } quit: { [weak self] in
            self?.quit()
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
            waiter.timeout?.cancel()
            waiter.answer.resume(returning: Answer(reply: .refused("\(AppIdentity.appName) is quitting")))
        }
        waiters = [:]
        // An open `wait` ends with no reply: its command connects again.
        listeners.stop()
    }
}

