#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
import Foundation
import VRLease

/// How a request reaches the app: one connection to the socket, the
/// request written, everything the app writes back until it closes. The
/// real one is `UnixSocketTransport`; tests answer in memory.
public protocol ControlTransport: Sendable {
    /// `idleTimeout` is the longest silence accepted, not the longest
    /// exchange: a waiting connection's heartbeat keeps it open.
    func exchange(_ request: Data, socket: URL, idleTimeout: TimeInterval) throws(ControlTransportFailure) -> Data
}

/// Why an exchange over the socket didn't come back with a reply.
public enum ControlTransportFailure: Error, Equatable, Sendable {
    /// Nothing listens: no socket file, or a connection refused.
    case notRunning
    /// Connected, but the app stayed silent past the idle timeout.
    case timedOut
    /// Any other failure, in words.
    case failed(String)
}

/// The control socket through POSIX calls: connect, write the request,
/// half-close, read the reply to its end.
public struct UnixSocketTransport: ControlTransport {
    public init() {}

    public func exchange(_ request: Data, socket: URL, idleTimeout: TimeInterval) throws(ControlTransportFailure) -> Data {
        guard let address = UnixSocket.address(socket.path) else { throw .failed(UnixSocket.tooLong(socket.path)) }
        let descriptor = UnixSocket.make()
        guard descriptor >= 0 else { throw .failed("couldn't open a socket: \(UnixSocket.reason())") }
        defer { close(descriptor) }
        UnixSocket.configure(descriptor, timeout: idleTimeout)
        guard UnixSocket.connectSocket(descriptor, to: address) == 0 else {
            let code = errno
            // No file, or a file nobody listens on (left by an app that crashed).
            if code == ENOENT || code == ECONNREFUSED { throw .notRunning }
            throw .failed("couldn't reach \(socket.path): \(UnixSocket.reason(code))")
        }
        guard UnixSocket.writeAll(descriptor, request) else {
            throw .failed("couldn't send the request: \(UnixSocket.reason())")
        }
        UnixSocket.finishWriting(descriptor)
        switch UnixSocket.readToEnd(descriptor) {
        case .data(let reply): return reply
        case .timedOut: throw .timedOut
        case .failed(let why): throw .failed("couldn't read the reply: \(why)")
        }
    }
}

/// Sends one request to the running app and reads its reply.
public struct ControlClient: Sendable {
    /// The socket, from `ControlSocket.locate(support:)`.
    public var socket: URL
    /// Who every request is sent as (`Holder.find`).
    public var holder: Holder
    public var transport: any ControlTransport
    /// The longest silence accepted while the reply is awaited. The app
    /// writes a heartbeat every two seconds until it answers, so this only
    /// runs out on an app that hangs.
    public var idleTimeout: TimeInterval

    public static let defaultIdleTimeout: TimeInterval = 15

    public init(socket: URL, holder: Holder, transport: any ControlTransport, idleTimeout: TimeInterval = ControlClient.defaultIdleTimeout) {
        self.socket = socket
        self.holder = holder
        self.transport = transport
        self.idleTimeout = idleTimeout
    }

    public enum Failure: Error, Equatable, Sendable {
        /// The app isn't running.
        case notRunning
        /// The app stayed silent for this long.
        case timedOut(TimeInterval)
        /// The exchange failed, or the reply didn't read: why.
        case failed(String)
    }

    public func send(_ request: ControlRequest, json: Bool = false) -> Result<ControlReply, Failure> {
        // A request the app answers late on purpose (a `wait`, a take in
        // line) needs no longer timeout: the app's heartbeat breaks the silence.
        let data: Data
        do throws(ControlTransportFailure) {
            data = try transport.exchange(
                ControlMessage(request, holder: holder, json: json).encoded(), socket: socket, idleTimeout: idleTimeout
            )
        } catch {
            switch error {
            case .notRunning: return .failure(.notRunning)
            case .timedOut: return .failure(.timedOut(idleTimeout))
            case .failed(let why): return .failure(.failed(why))
            }
        }
        do throws(ControlProtocolError) {
            return .success(try ControlReply.decode(data))
        } catch {
            return .failure(.failed(
                "\(error.message); is the app from the same build as this video-review (\(Identity.version), \(Identity.appName))?"
            ))
        }
    }
}
