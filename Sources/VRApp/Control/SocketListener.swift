import Darwin
import Foundation
import VRWire

/// The listening socket's POSIX side, off the main actor: accepts each
/// connection on its own queue, reads the request to its end, has the
/// server answer it, writes the reply and closes. While the answer is
/// awaited, a heartbeat of one space is written to the connection: the
/// client's idle timeout never fires on a healthy wait, and a client that
/// has gone is found out, which cancels the request's task. An answer that
/// hands something over (the lease, a batch) goes back to the server once
/// its reply was written (`written`) or couldn't be (`undelivered`).
final class SocketListener: @unchecked Sendable {
    typealias Respond = @Sendable (Data) async -> ControlServer.Answer
    typealias Undelivered = @MainActor @Sendable (ControlServer.Answer) -> Void
    typealias Written = @MainActor @Sendable (ControlServer.Answer) -> Void

    /// How often a waiting connection is written to. A JSON reader skips
    /// the spaces before the reply.
    static let heartbeat: Duration = .seconds(2)

    /// Why the socket couldn't be listened on.
    struct Failure: Error, CustomStringConvertible {
        var description: String
    }

    private let path: String
    private let source: DispatchSourceRead
    private let respond: Respond
    private let heartbeat: Duration
    private let written: Written
    private let undelivered: Undelivered
    private let quit: @MainActor @Sendable () -> Void
    private static let queue = DispatchQueue(label: "video-review.control", attributes: .concurrent)
    /// How long a connection may take to send its request or read the
    /// reply, so a client that stalls never holds a thread.
    private static let connectionTimeout: TimeInterval = 5
    /// The most bytes read of one request.
    private static let largestRequest = 8 << 20

    private init(
        path: String, descriptor: Int32, heartbeat: Duration, respond: @escaping Respond, written: @escaping Written,
        undelivered: @escaping Undelivered, quit: @escaping @MainActor @Sendable () -> Void
    ) {
        self.path = path
        self.heartbeat = heartbeat
        self.respond = respond
        self.written = written
        self.undelivered = undelivered
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
    /// request; an answer that hands something over goes to `written` once
    /// its reply was written, or to `undelivered` when it couldn't be;
    /// `quit` runs once a reply that says so is written.
    static func open(
        at socket: URL, heartbeat: Duration = SocketListener.heartbeat, respond: @escaping Respond,
        written: @escaping Written, undelivered: @escaping Undelivered, quit: @escaping @MainActor @Sendable () -> Void
    ) throws(Failure) -> SocketListener {
        let path = socket.path
        guard let address = UnixSocket.address(path) else { throw Failure(description: UnixSocket.tooLong(path)) }
        do {
            try FileManager.default.createDirectory(at: socket.deletingLastPathComponent(), withIntermediateDirectories: true)
        } catch {
            throw Failure(description: "couldn't create \(socket.deletingLastPathComponent().path): \(error.localizedDescription)")
        }
        if FileManager.default.fileExists(atPath: path) {
            guard !answers(address) else { throw Failure(description: "another app already listens on \(path)") }
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
            path: path, descriptor: descriptor, heartbeat: heartbeat, respond: respond, written: written,
            undelivered: undelivered, quit: quit
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
    /// something can't be written to it: a heartbeat, which cancels the
    /// request's task, or the reply, which hands back what it carried.
    private func serve(_ connection: Int32) {
        guard case .data(let request) = UnixSocket.readToEnd(connection, limit: Self.largestRequest), !request.isEmpty else {
            Darwin.close(connection)
            return
        }
        let respond = respond
        let heartbeat = heartbeat
        let written = written
        let undelivered = undelivered
        let quit = quit
        Task {
            let answering = Task { await respond(request) }
            let beating = Task {
                while true {
                    do { try await Task.sleep(for: heartbeat) } catch { return }
                    guard UnixSocket.writeAll(connection, Data([0x20])) else {
                        // The client has gone: whatever waits for it stops waiting.
                        answering.cancel()
                        return
                    }
                }
            }
            let answer = await answering.value
            // The heartbeat has stopped before the reply is written, so
            // the two never mix and nothing is written after the close.
            beating.cancel()
            await beating.value
            let delivered = UnixSocket.writeAll(connection, answer.reply.encoded())
            Darwin.close(connection)
            if answer.handsOver {
                if delivered { await written(answer) } else { await undelivered(answer) }
            }
            if answer.quits { await quit() }
        }
    }
}
