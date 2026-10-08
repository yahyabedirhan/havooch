#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif
import Foundation
import ReviewLease

/// How a request reaches the app: one connection to the socket, the
/// request written, everything the app writes back until it closes. The
/// real one is `UnixSocketTransport`; tests answer in memory.
public protocol ControlTransport: Sendable {
    /// `timeout` nil waits for the reply with no limit.
    func exchange(_ request: Data, socket: URL, timeout: TimeInterval?) throws(ControlTransportFailure) -> Data
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

    public func exchange(_ request: Data, socket: URL, timeout: TimeInterval?) throws(ControlTransportFailure) -> Data {
        // No file is no app, whatever the path's length.
        guard FileManager.default.fileExists(atPath: socket.path) else { throw .notRunning }
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
    /// Whether the caller passed `--json`.
    public var json: Bool
    public var transport: any ControlTransport
    /// How long to wait for the reply. Opening a video or a screenshot
    /// takes a moment, so it's generous; a request the app may hold adds
    /// its `holdSeconds`.
    public var timeout: TimeInterval

    public static let defaultTimeout: TimeInterval = 15

    public init(
        socket: URL, holder: Holder, json: Bool = false, transport: any ControlTransport,
        timeout: TimeInterval = ControlClient.defaultTimeout
    ) {
        self.socket = socket
        self.holder = holder
        self.json = json
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

    /// Sends `request` for the window `window` names (`--window`), or
    /// the key window when it's nil.
    public func send(_ request: ControlRequest, window: String? = nil) -> Result<ControlReply, Failure> {
        let data: Data
        let limit = request.holdSeconds.map { timeout + $0 }
        do throws(ControlTransportFailure) {
            data = try transport.exchange(
                ControlMessage(request, holder: holder, json: json, window: window).encoded(), socket: socket, timeout: limit
            )
        } catch {
            switch error {
            case .notRunning: return .failure(.notRunning)
            case .timedOut: return .failure(.timedOut(limit ?? 0))
            case .failed(let why): return .failure(.failed(why))
            }
        }
        // An app that goes away while it holds a request closes with no
        // reply, after its heartbeat's spaces at most.
        if data.allSatisfy({ $0 == UInt8(ascii: " ") }) { return .failure(.notRunning) }
        do throws(ControlProtocolError) {
            return .success(try ControlReply.decode(data))
        } catch {
            return .failure(.failed(
                "\(error.message); is the app from the same build as this havooch (\(Version.app))?"
            ))
        }
    }
}
