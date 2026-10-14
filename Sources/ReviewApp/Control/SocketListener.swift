import Darwin
import Foundation
import ReviewWire

nonisolated final class SocketListener: @unchecked Sendable {
    typealias Respond = @Sendable (Data, UUID) async -> ControlServer.Answer
    typealias Delivered = @MainActor @Sendable (ControlServer.Answer) -> Void
    typealias HungUp = @MainActor @Sendable (UUID) -> Void

    struct Failure: Error, CustomStringConvertible {
        var description: String
    }

    static let heartbeat: Duration = .seconds(2)

    private let path: String
    private let source: any DispatchSourceRead
    private let heartbeat: Duration
    private let respond: Respond
    private let written: Delivered
    private let undelivered: Delivered
    private let hungUp: HungUp
    private let quit: @MainActor @Sendable () -> Void
    private static let queue = DispatchQueue(label: "havooch.control", attributes: .concurrent)
    private static let connectionTimeout: TimeInterval = 5

    private init(
        path: String, descriptor: Int32, heartbeat: Duration, respond: @escaping Respond, written: @escaping Delivered,
        undelivered: @escaping Delivered, hungUp: @escaping HungUp, quit: @escaping @MainActor @Sendable () -> Void
    ) {
        self.path = path
        self.heartbeat = heartbeat
        self.respond = respond
        self.written = written
        self.undelivered = undelivered
        self.hungUp = hungUp
        self.quit = quit
        source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: Self.queue)
        source.setEventHandler { [weak self] in self?.acceptAll(descriptor) }
        source.setCancelHandler { Darwin.close(descriptor) }
        source.resume()
    }

    static func open(
        at socket: URL, heartbeat: Duration = SocketListener.heartbeat, respond: @escaping Respond, written: @escaping Delivered,
        undelivered: @escaping Delivered, hungUp: @escaping HungUp, quit: @escaping @MainActor @Sendable () -> Void
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
        guard UnixSocket.bindSocket(descriptor, to: address) == 0, chmod(path, 0o600) == 0,
              listen(descriptor, 16) == 0, fcntl(descriptor, F_SETFL, O_NONBLOCK) == 0 else {
            let why = UnixSocket.reason()
            Darwin.close(descriptor)
            unlink(path)
            throw Failure(description: "couldn't listen on \(path): \(why)")
        }
        return SocketListener(
            path: path, descriptor: descriptor, heartbeat: heartbeat, respond: respond, written: written,
            undelivered: undelivered, hungUp: hungUp, quit: quit
        )
    }

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

    private func acceptAll(_ descriptor: Int32) {
        while true {
            let connection = accept(descriptor, nil, nil)
            guard connection >= 0 else { return }
            _ = fcntl(connection, F_SETFL, fcntl(connection, F_GETFL) & ~O_NONBLOCK)
            UnixSocket.configure(connection, timeout: Self.connectionTimeout)
            Self.queue.async { self.serve(connection) }
        }
    }

    private func serve(_ connection: Int32) {
        guard case .data(let request) = UnixSocket.readToEnd(connection, limit: ControlRequest.largestMessage), !request.isEmpty else {
            Darwin.close(connection)
            return
        }
        let respond = respond
        let written = written
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
                        await hungUp(id)
                        return
                    }
                }
            }
            let answer = await respond(request, id)
            beating.cancel()
            await beating.value
            let delivered = !answer.silent && UnixSocket.writeAll(connection, answer.reply.encoded())
            Darwin.close(connection)
            if delivered { await written(answer) } else { await undelivered(answer) }
            if answer.quits { await quit() }
        }
    }
}
