import Darwin
import Foundation
import ReviewWire

/// Why the app refuses an action, as the one line the command prints.
struct AppRefusal: Error, Equatable {
    var reason: String

    init(_ reason: String) {
        self.reason = reason
    }
}

/// The app as the control server drives it: the actions an operator can
/// take. `AppModel` is the real one; the server's tests use a fake.
@MainActor
protocol AppControlling: AnyObject {
    func state() -> StateReport
    func open(_ url: URL) async throws(AppRefusal)
    func play() throws(AppRefusal)
    func pause() throws(AppRefusal)
    func seek(to seconds: Double) async throws(AppRefusal)
}

/// App control's server: while the app runs it listens on `control.sock`
/// in the support folder, the user's own (mode 0600), and answers one JSON
/// request per connection with one reply. Each request is read off the main
/// actor, answered on it (`reply(to:)`), and the reply written back before
/// the connection closes. Every refusal is a reply, so the `video-review`
/// command always has a line to print.
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
    private let app: any AppControlling
    private let screenshotter: any Screenshotting
    private let quit: @MainActor () -> Void
    private var listener: Listener?

    init(socket: URL, app: any AppControlling, screenshotter: any Screenshotting, quit: @escaping @MainActor () -> Void) {
        self.socket = socket
        self.app = app
        self.screenshotter = screenshotter
        self.quit = quit
    }

    // MARK: - Dispatch

    /// The answer to one request as the client sent it. A request that
    /// doesn't read, or speaks another version, is refused before anything
    /// is done.
    func reply(to data: Data) async -> Answer {
        let message: ControlMessage
        do throws(ControlProtocolError) {
            message = try ControlMessage.decode(data)
        } catch {
            return Answer(reply: .refused(error.message))
        }
        // Every holder is admitted: a request's role (`request.role`) and
        // its holder are what the lease decides on, here, before dispatch.
        let json = message.json
        do throws(AppRefusal) {
            switch message.request {
            case .appStatus, .appOpen:
                let state = app.state()
                return done(json ? state.statusJSON : state.statusLines)
            case .state:
                let state = app.state()
                return done(json ? state.json : state.lines)
            case .appQuit:
                let line = "\(AppIdentity.appName) quit"
                return Answer(reply: .done(json ? StateReport.json(Output(quit: true)) : line + "\n"), quits: true)
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
            case .screenshot(let path, let appearance):
                try await screenshotter.capture(to: URL(fileURLWithPath: path), appearance: appearance)
                return done(path, Output(path: path), json)
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
    }

    private func done(_ output: String) -> Answer {
        Answer(reply: .done(output))
    }

    /// Done: `line`, or `output` as JSON when the caller passed `--json`.
    private func done(_ line: String, _ output: Output, _ json: Bool) -> Answer {
        Answer(reply: .done(json ? StateReport.json(output) : line + "\n"))
    }

    // MARK: - Listening

    /// Starts listening, creating the support folder when it's missing. A
    /// socket file nothing answers on (left by an app that crashed) is
    /// replaced; one another app answers on is left alone, and this one
    /// doesn't listen.
    func start() throws(Failure) {
        guard listener == nil else { return }
        listener = try Listener.open(at: socket) { [weak self] data in
            await self?.reply(to: data) ?? Answer(reply: .refused("\(AppIdentity.appName) is quitting"))
        } quit: { [weak self] in
            self?.quit()
        }
    }

    /// Stops listening and removes the socket, so the `video-review`
    /// command finds the app gone.
    func stop() {
        listener?.close()
        listener = nil
    }
}

/// The listening socket's POSIX side, off the main actor: accepts each
/// connection on its own queue, reads the request to its end, has the
/// server answer it, writes the reply and closes.
private final class Listener: @unchecked Sendable {
    typealias Respond = @Sendable (Data) async -> ControlServer.Answer

    private let path: String
    private let source: any DispatchSourceRead
    private let respond: Respond
    private let quit: @MainActor @Sendable () -> Void
    private static let queue = DispatchQueue(label: "video-review.control", attributes: .concurrent)
    /// How long a connection may take to send its request or read the
    /// reply, so a client that stalls never holds a thread.
    private static let connectionTimeout: TimeInterval = 5

    private init(path: String, descriptor: Int32, respond: @escaping Respond, quit: @escaping @MainActor @Sendable () -> Void) {
        self.path = path
        self.respond = respond
        self.quit = quit
        source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: Self.queue)
        source.setEventHandler { [weak self] in self?.acceptAll(descriptor) }
        source.setCancelHandler { Darwin.close(descriptor) }
        source.resume()
    }

    static func open(
        at socket: URL, respond: @escaping Respond, quit: @escaping @MainActor @Sendable () -> Void
    ) throws(ControlServer.Failure) -> Listener {
        let path = socket.path
        do {
            try FileManager.default.createDirectory(at: socket.deletingLastPathComponent(), withIntermediateDirectories: true)
        } catch {
            throw .init(description: "couldn't create \(socket.deletingLastPathComponent().path): \(error.localizedDescription)")
        }
        guard let address = UnixSocket.address(path) else { throw .init(description: UnixSocket.tooLong(path)) }
        if FileManager.default.fileExists(atPath: path) {
            guard !answers(address) else { throw .init(description: "another \(AppIdentity.appName) already listens on \(path)") }
            unlink(path)
        }
        let descriptor = UnixSocket.make()
        guard descriptor >= 0 else { throw .init(description: "couldn't open a socket: \(UnixSocket.reason())") }
        // Owner-only before anyone can connect: connections wait for listen(2).
        guard UnixSocket.bindSocket(descriptor, to: address) == 0, chmod(path, 0o600) == 0,
              listen(descriptor, 16) == 0, fcntl(descriptor, F_SETFL, O_NONBLOCK) == 0 else {
            let why = UnixSocket.reason()
            Darwin.close(descriptor)
            unlink(path)
            throw .init(description: "couldn't listen on \(path): \(why)")
        }
        return Listener(path: path, descriptor: descriptor, respond: respond, quit: quit)
    }

    /// Whether something accepts a connection at `address`.
    private static func answers(_ address: sockaddr_un) -> Bool {
        let probe = UnixSocket.make()
        guard probe >= 0 else { return false }
        defer { Darwin.close(probe) }
        return UnixSocket.connectSocket(probe, to: address) == 0
    }

    func close() {
        source.cancel()
        unlink(path)
    }

    /// Accepts every waiting connection; the listening socket doesn't block.
    private func acceptAll(_ descriptor: Int32) {
        while true {
            let connection = accept(descriptor, nil, nil)
            guard connection >= 0 else { return }
            // An accepted socket inherits O_NONBLOCK; its reads wait, up to the timeout.
            _ = fcntl(connection, F_SETFL, fcntl(connection, F_GETFL) & ~O_NONBLOCK)
            UnixSocket.configure(connection, timeout: Self.connectionTimeout)
            Self.queue.async { self.serve(connection) }
        }
    }

    /// Answers one connection. One that sends nothing, such as another
    /// app's look at whether this one listens, gets no reply.
    private func serve(_ connection: Int32) {
        guard case .data(let request) = UnixSocket.readToEnd(connection, limit: ControlRequest.largestMessage), !request.isEmpty else {
            Darwin.close(connection)
            return
        }
        let respond = respond
        let quit = quit
        Task {
            let answer = await respond(request)
            _ = UnixSocket.writeAll(connection, answer.reply.encoded())
            Darwin.close(connection)
            if answer.quits { await quit() }
        }
    }
}
