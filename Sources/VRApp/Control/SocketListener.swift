import Darwin
import Foundation
import VRWire

/// The listening socket's POSIX side, off the main actor: accepts each
/// connection on its own queue, reads the request to its end, has the server
/// answer it, writes the reply and closes.
final class SocketListener: @unchecked Sendable {
    typealias Respond = @Sendable (Data) async -> ControlServer.Answer

    private let path: String
    private let source: DispatchSourceRead
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

    /// Listens at `socket`, owner-only. `respond` answers each request;
    /// `quit` runs after a reply that says the app quits has been written.
    static func open(
        at socket: URL,
        respond: @escaping Respond,
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
        return SocketListener(path: path, descriptor: descriptor, respond: respond, quit: quit)
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
