import Foundation
import VRLease
import VRWire

/// App control's server: while the app runs it listens on `control.sock` in
/// the support folder and answers one JSON request per connection with one
/// reply. Each request is decoded, checked for its version, passed the
/// lease's gate when it's an operator's, and dispatched. Every refusal is a
/// reply, so the `video-review` command always has a line to print. A
/// `take`'s reply granting the lease that can't be written (its client gone)
/// gives the lease up at once.
@MainActor
final class ControlServer {
    /// A reply, whether the app quits once it's written, and the lease a
    /// `control take`'s reply grants, released when the reply can't be
    /// written (`undelivered`).
    struct Answer: Equatable {
        var reply: ControlReply
        var quits = false
        var granted: ControlLease.Term?
    }

    /// Why the server couldn't start listening.
    struct Failure: Error, CustomStringConvertible {
        var description: String
    }

    let socket: URL
    private let model: ReviewModel
    private let desk: OperatorDesk
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

    /// A `take` waiting in line: who sent it, how long it waits, how it
    /// wants its answer and how it gets it.
    private struct Waiter {
        var holder: Holder
        var seconds: Int
        var json: Bool
        var answer: CheckedContinuation<Answer, Never>
        /// Ends the wait when it runs out; cancelled once it's answered.
        var timeout: Task<Void, Never>?
    }

    init(
        socket: URL,
        model: ReviewModel,
        desk: OperatorDesk,
        lease: ControlLease = ControlLease(),
        indicator: LeaseIndicator = LeaseIndicator(),
        now: @escaping @MainActor () -> Date = { Date() },
        timeZone: TimeZone = .current,
        quit: @escaping @MainActor () -> Void
    ) {
        self.socket = socket
        self.model = model
        self.desk = desk
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

    /// The answer to one request as the client sent it. An operator's
    /// request asks the lease first: refused for anyone but its holder, with
    /// nothing done. A quit hands the lease back in its reply, for a
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
        var held: ControlLease.Term?
        if message.request.role == .operator {
            let time = now()
            switch lease.use(by: message.holder, at: time).answer {
            case .success(let term): held = term
            case .failure(let refusal): return Answer(reply: .refused(refusal.message(at: time, timeZone: timeZone)))
            }
        }
        let json = message.json
        switch message.request {
        case .controlTake(let seconds):
            return await take(by: message.holder, waiting: seconds, json: json)
        case .controlRelease:
            // The next waiter's take is answered as the lease changes (`leaseChanged`).
            let released = lease.release(by: message.holder, at: now()).contains {
                if case .ended(let holder, .released) = $0 { holder.key == message.holder.key } else { false }
            }
            // `released` is false when the sender held nothing to give up.
            struct Released: Encodable { var released: Bool }
            return Answer(reply: .done(json ? JSONLine.string(Released(released: released)) : "released video-review\n"))
        case .appStatus, .appOpen:
            let report = report()
            return Answer(reply: .done(json ? report.statusJSON : report.statusText))
        case .state:
            let report = report()
            return Answer(reply: .done(json ? report.stateJSON : report.stateText))
        case .appQuit:
            struct Quit: Encodable { var quit = true }
            let output = json ? JSONLine.string(Quit()) : "video-review quit\n"
            return Answer(reply: ControlReply(ok: true, output: output, lease: held), quits: true)
        case .playerOpen(let path):
            return Answer(reply: await desk.open(path, json: json))
        case .playerPlay:
            return Answer(reply: await desk.play(json: json))
        case .playerPause:
            return Answer(reply: await desk.pause(json: json))
        case .playerSeek(let seconds):
            return Answer(reply: await desk.seek(to: seconds, json: json))
        case .screenshot(let path, let appearance):
            return Answer(reply: await desk.screenshot(to: path, appearance: appearance, json: json))
        }
    }

    /// What the app shows, with the lease as it is now.
    private func report() -> StateReport {
        StateReport(model: model, lease: lease.status(at: now()))
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
            return held(term, json: json)
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
            let timeout = Task { @MainActor [weak self] in
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

    /// A `take`'s answer holding the lease to `term`'s end, which it grants:
    /// `you hold video-review until 12:05:00`, or `{held, until}`.
    private func held(_ term: ControlLease.Term, json: Bool) -> Answer {
        struct Held: Encodable { var held = true; var until: String }
        let output = json
            ? JSONLine.string(Held(until: term.ends.formatted(.iso8601)))
            : term.held(timeZone: timeZone) + "\n"
        return Answer(reply: .done(output), granted: term)
    }

    /// A `take`'s reply that granted the lease couldn't be written: its
    /// client has gone (stopped, or cut off by its harness's timeout while
    /// it waited in line), so nobody knows they hold it. The lease is given
    /// up for that holder at once, and the next waiter gets it as usual,
    /// rather than it sitting unused until it runs out. A lease that has
    /// moved on meanwhile (another holder's, or a new one) is left alone.
    func undelivered(_ answer: Answer) {
        guard let granted = answer.granted, let term = lease.current(at: now()),
              term.holder.key == granted.holder.key, term.taken == granted.taken else { return }
        _ = lease.release(by: granted.holder, at: now())
    }

    // MARK: - The person taking the app back

    /// The banner's Stop: the holder's lease ends and it's barred
    /// (`ControlLease.stop`), and the first waiter in line gets the lease,
    /// its `take` answered as the lease changes. The person's only way into
    /// the lease.
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
                waiter.timeout?.cancel()
                waiter.answer.resume(returning: held(term, json: waiter.json))
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

    /// Starts listening, creating the support folder when it's missing. A
    /// socket file nothing answers on (left by an app that crashed) is
    /// replaced; one another app answers on is left alone, and this one
    /// doesn't listen.
    func start() throws(Failure) {
        guard listener == nil else { return }
        listener = try SocketListener.open(at: socket) { [weak self] data in
            await self?.reply(to: data) ?? Answer(reply: .refused("video-review is quitting"))
        } undelivered: { [weak self] answer in
            self?.undelivered(answer)
        } quit: { [weak self] in
            self?.quit()
        }
    }

    /// Stops listening and removes the socket, so the `video-review` command
    /// finds the app gone.
    func stop() {
        listener?.close()
        listener = nil
        settling?.cancel()
        settling = nil
        // A take waiting in line hears why, rather than a dropped connection.
        for waiter in waiters.values {
            waiter.timeout?.cancel()
            waiter.answer.resume(returning: Answer(reply: .refused("video-review is quitting")))
        }
        waiters = [:]
    }
}
