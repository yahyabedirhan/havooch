import Foundation
import VRLease
import VRWire

/// App control's server: while the app runs it listens on `control.sock` in
/// the support folder and answers one JSON request per connection with one
/// reply. Each request is decoded, checked for its version, passed the
/// lease's gate when it's an operator's, and dispatched. Every refusal is a
/// reply, so the `video-review` command always has a line to print.
@MainActor
final class ControlServer {
    /// A reply, and whether the app quits once it's written.
    struct Answer: Equatable {
        var reply: ControlReply
        var quits = false
    }

    /// Why the server couldn't start listening.
    struct Failure: Error, CustomStringConvertible {
        var description: String
    }

    let socket: URL
    private let model: ReviewModel
    private let desk: OperatorDesk
    private let quit: @MainActor () -> Void
    /// The time the lease is decided at.
    private let now: @MainActor () -> Date
    /// App control's lease: who may send operator requests, and until when.
    private var lease = ControlLease()
    private var listener: SocketListener?

    init(
        socket: URL,
        model: ReviewModel,
        desk: OperatorDesk,
        now: @escaping @MainActor () -> Date = { Date() },
        quit: @escaping @MainActor () -> Void
    ) {
        self.socket = socket
        self.model = model
        self.desk = desk
        self.now = now
        self.quit = quit
    }

    // MARK: - Dispatch

    /// The answer to one request as the client sent it. An operator's
    /// request asks the lease first: refused for anyone but its holder, with
    /// nothing done.
    func reply(to data: Data) async -> Answer {
        let message: ControlMessage
        do throws(ControlProtocolError) {
            message = try ControlMessage.decode(data)
        } catch {
            return Answer(reply: .refused(error.message))
        }
        if message.request.role == .operator {
            if case .failure(let refusal) = lease.use(by: message.holder, at: now()).answer {
                return Answer(reply: .refused(refusal.message))
            }
        }
        let json = message.json
        switch message.request {
        case .appStatus, .appOpen:
            let report = report()
            return Answer(reply: .done(json ? report.statusJSON : report.statusText))
        case .state:
            let report = report()
            return Answer(reply: .done(json ? report.stateJSON : report.stateText))
        case .appQuit:
            struct Quit: Encodable { var quit = true }
            return Answer(reply: .done(json ? JSONLine.string(Quit()) : "video-review quit\n"), quits: true)
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

    // MARK: - Listening

    /// Starts listening, creating the support folder when it's missing. A
    /// socket file nothing answers on (left by an app that crashed) is
    /// replaced; one another app answers on is left alone, and this one
    /// doesn't listen.
    func start() throws(Failure) {
        guard listener == nil else { return }
        listener = try SocketListener.open(at: socket) { [weak self] data in
            await self?.reply(to: data) ?? Answer(reply: .refused("video-review is quitting"))
        } quit: { [weak self] in
            self?.quit()
        }
    }

    /// Stops listening and removes the socket, so the `video-review` command
    /// finds the app gone.
    func stop() {
        listener?.close()
        listener = nil
    }
}
