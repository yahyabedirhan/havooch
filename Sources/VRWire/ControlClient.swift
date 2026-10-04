import Darwin
import Foundation
import VRLease

/// How a request reaches the app: one connection to the socket, the request
/// written, everything the app writes back until it closes. The real one is
/// `UnixSocketTransport`; tests answer in memory.
public protocol ControlTransport: Sendable {
    func exchange(_ request: Data, socket: URL, timeout: TimeInterval) throws(ControlTransportFailure) -> Data
}

/// Why an exchange over the socket didn't come back with a reply.
public enum ControlTransportFailure: Error, Equatable, Sendable {
    /// Nothing listens: no socket file, or a connection refused.
    case notRunning
    /// Connected, but the app wrote no reply in time.
    case timedOut
    /// Any other failure, in words.
    case failed(String)
}

/// `control.sock` through POSIX calls: connect, write the request,
/// half-close, read the reply to its end.
public struct UnixSocketTransport: ControlTransport {
    public init() {}

    public func exchange(_ request: Data, socket: URL, timeout: TimeInterval) throws(ControlTransportFailure) -> Data {
        guard let address = UnixSocket.address(socket.path) else { throw .failed(UnixSocket.tooLong(socket.path)) }
        let descriptor = UnixSocket.make()
        guard descriptor >= 0 else { throw .failed("couldn't open a socket: \(UnixSocket.reason())") }
        defer { close(descriptor) }
        UnixSocket.configure(descriptor, timeout: timeout)
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
    /// How long to wait for the reply. Opening a video and taking a
    /// screenshot take a moment, so it's generous.
    public var timeout: TimeInterval

    public static let defaultTimeout: TimeInterval = 15
    /// How long a long poll's connection may stay silent. The app writes a
    /// heartbeat every few seconds while it holds one, so a silence this
    /// long means the app died, however long the poll itself may take.
    public static let longestSilence: TimeInterval = 10

    public init(socket: URL, holder: Holder, transport: any ControlTransport, timeout: TimeInterval = ControlClient.defaultTimeout) {
        self.socket = socket
        self.holder = holder
        self.transport = transport
        self.timeout = timeout
    }

    public enum Failure: Error, Equatable, Sendable {
        /// The app isn't running.
        case notRunning
        /// The app didn't answer within the timeout.
        case timedOut(TimeInterval)
        /// The exchange failed, or the reply didn't read: why.
        case failed(String)
    }

    /// Sends `request`, asking for JSON output when `json` is set. A request
    /// the app may hold before it answers (a `take` waiting in line) is
    /// waited for that much longer. A long poll (`wait`) is waited for as
    /// long as the app keeps its connection alive.
    public func send(_ request: ControlRequest, json: Bool = false) -> Result<ControlReply, Failure> {
        let timeout = request.isLongPoll ? Self.longestSilence : timeout + request.hold
        let data: Data
        do throws(ControlTransportFailure) {
            let message = ControlMessage(request, holder: holder, json: json)
            data = try transport.exchange(message.encoded(), socket: socket, timeout: timeout)
        } catch {
            switch error {
            case .notRunning: return .failure(.notRunning)
            case .timedOut: return .failure(.timedOut(timeout))
            case .failed(let why): return .failure(.failed(why))
            }
        }
        do throws(ControlProtocolError) {
            return .success(try ControlReply.decode(data))
        } catch {
            return .failure(.failed(
                "\(error.message); is the app from the same build as this video-review (\(AppIdentity.versionText))?"
            ))
        }
    }
}
