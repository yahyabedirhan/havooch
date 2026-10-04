import Darwin
import Foundation
import VRWire

/// The listening socket's POSIX side, off the main actor: accepts each
/// connection on its own queue, reads the request to its end, has the server
/// answer it, writes the reply and closes. While the server holds a long
/// poll's connection, a heartbeat is written to it, so both ends notice the
/// other going away. How writing a reply went that something hangs on (a
/// granted lease, a delivered batch) goes back to the server (`written`).
final class SocketListener: @unchecked Sendable {
    typealias Respond = @Sendable (Data, UUID) async -> ControlServer.Answer
    typealias Written = @MainActor @Sendable (ControlServer.Answer, Bool) -> Void
    typealias Dropped = @MainActor @Sendable (UUID) -> Void

    private let path: String
    private let source: DispatchSourceRead
    private let respond: Respond
    private let written: Written
    private let dropped: Dropped
    private let quit: @MainActor @Sendable () -> Void
    private let heartbeat: TimeInterval
    private static let queue = DispatchQueue(label: "video-review.control", attributes: .concurrent)
    /// How long a connection may take to send its request or read the
    /// reply, so a client that stalls never holds a thread.
    private static let connectionTimeout: TimeInterval = 5
    /// How often a held connection gets its heartbeat, in seconds: well
    /// inside the silence the client allows (`ControlClient.longestSilence`).
    static let heartbeat: TimeInterval = 2

    private init(
        path: String, descriptor: Int32, heartbeat: TimeInterval, respond: @escaping Respond, written: @escaping Written,
        dropped: @escaping Dropped, quit: @escaping @MainActor @Sendable () -> Void
    ) {
        self.path = path
        self.heartbeat = heartbeat
        self.respond = respond
        self.written = written
        self.dropped = dropped
        self.quit = quit
        source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: Self.queue)
        source.setEventHandler { [weak self] in self?.acceptAll(descriptor) }
        source.setCancelHandler { Darwin.close(descriptor) }
        source.resume()
    }

    /// Listens at `socket`, owner-only. `respond` answers each request,
    /// given a ticket that names its connection; `written` hears how
    /// writing a reply went that something hangs on; `dropped` hears of a
    /// held connection whose heartbeat couldn't be written; `quit` runs
    /// after a reply that says the app quits.
    static func open(
        at socket: URL,
        heartbeat: TimeInterval = SocketListener.heartbeat,
        respond: @escaping Respond,
        written: @escaping Written,
        dropped: @escaping Dropped,
        quit: @escaping @MainActor @Sendable () -> Void
    ) throws(ControlServer.Failure) -> SocketListener {
        let path = socket.path
        guard let address = UnixSocket.address(path) else { throw .init(description: UnixSocket.tooLong(path)) }
        do {
            try FileManager.default.createDirectory(at: socket.deletingLastPathComponent(), withIntermediateDirectories: true)
        } catch {
            throw .init(description: "couldn't create \(socket.deletingLastPathComponent().path): \(error.localizedDescription)")
        }
        if FileManager.default.fileExists(atPath: path) {
            guard !answers(address) else { throw .init(description: "another video-review already listens on \(path)") }
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
        return SocketListener(
            path: path, descriptor: descriptor, heartbeat: heartbeat, respond: respond, written: written, dropped: dropped, quit: quit
        )
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
    /// app's look at whether this one listens, gets no reply. The client
    /// half-closes once it has sent, so its hanging up shows only when
    /// something can't be written: the reply, or a long poll's heartbeat.
    private func serve(_ connection: Int32) {
        guard case .data(let request) = UnixSocket.readToEnd(connection, limit: ControlRequest.largestMessage), !request.isEmpty else {
            Darwin.close(connection)
            return
        }
        let respond = respond
        let written = written
        let dropped = dropped
        let quit = quit
        let ticket = UUID()
        let pulse = ControlServer.isLongPoll(request)
            ? Pulse(connection: connection, every: heartbeat, on: Self.queue) { Task { await dropped(ticket) } }
            : nil
        Task {
            let answer = await respond(request, ticket)
            let reply = answer.reply.encoded()
            let delivered = pulse?.finish(writing: reply) ?? UnixSocket.writeAll(connection, reply)
            Darwin.close(connection)
            if answer.hangsOnDelivery { await written(answer, delivered) }
            if answer.quits { await quit() }
        }
    }
}

/// A held connection's heartbeat: one space byte every few seconds until the
/// reply is written. JSON ignores space before it, so the reply still
/// reads. A beat that can't be written means the client is gone.
private final class Pulse: @unchecked Sendable {
    private let connection: Int32
    private let timer: DispatchSourceTimer
    private let lock = NSLock()
    /// Set once the reply is being written, or a beat failed: no more beats.
    private var isOver = false
    private var isGone = false

    init(connection: Int32, every interval: TimeInterval, on queue: DispatchQueue, gone: @escaping @Sendable () -> Void) {
        self.connection = connection
        timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + interval, repeating: interval)
        timer.setEventHandler { [weak self] in
            guard let self, self.beat() == false else { return }
            gone()
        }
        timer.resume()
    }

    /// Writes one beat; false when it couldn't be written, nil once the
    /// heartbeat is over.
    private func beat() -> Bool? {
        lock.withLock {
            guard !isOver else { return nil }
            if UnixSocket.writeAll(connection, Data([0x20])) { return true }
            isOver = true
            isGone = true
            timer.cancel()
            return false
        }
    }

    /// Ends the heartbeat and writes the reply after the last beat; false
    /// when it couldn't be written, or the client was gone already.
    func finish(writing reply: Data) -> Bool {
        lock.withLock {
            if !isOver { timer.cancel() }
            isOver = true
            return !isGone && UnixSocket.writeAll(connection, reply)
        }
    }
}
