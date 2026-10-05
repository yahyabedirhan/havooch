import Darwin
import Foundation
import ReviewWire

/// The listening socket's POSIX side, off the main actor: accepts each
/// connection on its own queue, reads the request to its end, has the
/// server answer it, writes the reply and closes. While the answer is
/// awaited, a heartbeat of one space is written to the connection every
/// `heartbeat`: the client's reads never sit idle on a healthy held request
/// (a JSON reader skips the spaces), and a heartbeat that can't be written
/// is a client that has gone, which the server hears (`hungUp`). A reply
/// that can't be written goes back to the server (`undelivered`).
///
/// Its reads block, up to the connection timeout, so they run on a
/// dispatch queue and not on the concurrency pool's few threads. It has no
/// mutable state: `@unchecked` only because the dispatch source isn't
/// declared `Sendable`.
nonisolated final class SocketListener: @unchecked Sendable {
    typealias Respond = @Sendable (Data, UUID) async -> ControlServer.Answer
    typealias Undelivered = @MainActor @Sendable (ControlServer.Answer) -> Void
    typealias HungUp = @MainActor @Sendable (UUID) -> Void

    /// Why the socket couldn't be listened on.
    struct Failure: Error, CustomStringConvertible {
        var description: String
    }

    /// How often a held connection is written to.
    static let heartbeat: Duration = .seconds(2)

    private let path: String
    private let source: any DispatchSourceRead
    private let heartbeat: Duration
    private let respond: Respond
    private let undelivered: Undelivered
    private let hungUp: HungUp
    private let quit: @MainActor @Sendable () -> Void
    private static let queue = DispatchQueue(label: "video-review.control", attributes: .concurrent)
    /// How long a connection may take to send its request or read the
    /// reply, so a client that stalls never holds a thread.
    private static let connectionTimeout: TimeInterval = 5

    private init(
        path: String, descriptor: Int32, heartbeat: Duration, respond: @escaping Respond, undelivered: @escaping Undelivered,
        hungUp: @escaping HungUp, quit: @escaping @MainActor @Sendable () -> Void
    ) {
        self.path = path
        self.heartbeat = heartbeat
        self.respond = respond
        self.undelivered = undelivered
        self.hungUp = hungUp
        self.quit = quit
        source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: Self.queue)
        source.setEventHandler { [weak self] in self?.acceptAll(descriptor) }
        source.setCancelHandler { Darwin.close(descriptor) }
        source.resume()
    }

    /// Starts listening at `socket`, the user's own (mode 0600), creating
    /// its folder when it's missing. A socket file nothing answers on (left
    /// by an app that crashed) is replaced; one another app answers on is
    /// left alone, and this one doesn't listen. `respond` answers each
    /// request; a reply that can't be written goes to `undelivered`; a
    /// client gone while its request is held goes to `hungUp`; `quit` runs
    /// once a reply that says so is written.
    static func open(
        at socket: URL, heartbeat: Duration = SocketListener.heartbeat, respond: @escaping Respond,
        undelivered: @escaping Undelivered, hungUp: @escaping HungUp, quit: @escaping @MainActor @Sendable () -> Void
    ) throws(Failure) -> SocketListener {
        let path = socket.path
        do {
            try FileManager.default.createDirectory(at: socket.deletingLastPathComponent(), withIntermediateDirectories: true)
        } catch {
            throw Failure(description: "couldn't create \(socket.deletingLastPathComponent().path): \(error.localizedDescription)")
        }
        guard let address = UnixSocket.address(path) else { throw Failure(description: UnixSocket.tooLong(path)) }
        if FileManager.default.fileExists(atPath: path) {
            guard !answers(address) else { throw Failure(description: "another \(AppIdentity.appName) already listens on \(path)") }
            unlink(path)
        }
        let descriptor = UnixSocket.make()
        guard descriptor >= 0 else { throw Failure(description: "couldn't open a socket: \(UnixSocket.reason())") }
        // Owner-only before anyone can connect: connections wait for listen(2).
        guard UnixSocket.bindSocket(descriptor, to: address) == 0, chmod(path, 0o600) == 0,
              listen(descriptor, 16) == 0, fcntl(descriptor, F_SETFL, O_NONBLOCK) == 0 else {
            let why = UnixSocket.reason()
            Darwin.close(descriptor)
            unlink(path)
            throw Failure(description: "couldn't listen on \(path): \(why)")
        }
        return SocketListener(
            path: path, descriptor: descriptor, heartbeat: heartbeat, respond: respond, undelivered: undelivered,
            hungUp: hungUp, quit: quit
        )
    }

    /// Whether something accepts a connection at `address`.
    private static func answers(_ address: sockaddr_un) -> Bool {
        let probe = UnixSocket.make()
        guard probe >= 0 else { return false }
        defer { Darwin.close(probe) }
        return UnixSocket.connectSocket(probe, to: address) == 0
    }

    /// Stops listening and removes the socket, so the `video-review`
    /// command finds the app gone.
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
    /// app's look at whether this one listens, gets no reply. The client
    /// half-closes once it has sent, so its hanging up shows only when
    /// something can't be written to it: a heartbeat, which tells the
    /// server the client is gone, or the reply, which hands back what it
    /// carried (a granted lease, a delivered send).
    private func serve(_ connection: Int32) {
        guard case .data(let request) = UnixSocket.readToEnd(connection, limit: ControlRequest.largestMessage), !request.isEmpty else {
            Darwin.close(connection)
            return
        }
        let respond = respond
        let heartbeat = heartbeat
        let undelivered = undelivered
        let hungUp = hungUp
        let quit = quit
        let id = UUID()
        Task {
            let beating = Task {
                while true {
                    do { try await Task.sleep(for: heartbeat) } catch { return }
                    guard UnixSocket.writeAll(connection, Data(" ".utf8)) else {
                        // The client has gone: whatever waits for it stops waiting.
                        await hungUp(id)
                        return
                    }
                }
            }
            let answer = await respond(request, id)
            // The heartbeat stops before the reply is written, so the two
            // never mix and nothing is written after the close.
            beating.cancel()
            await beating.value
            let delivered = !answer.silent && UnixSocket.writeAll(connection, answer.reply.encoded())
            Darwin.close(connection)
            if !delivered { await undelivered(answer) }
            if answer.quits { await quit() }
        }
    }
}
