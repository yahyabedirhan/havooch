import Darwin
import Foundation

/// The few POSIX calls both ends of the control socket make, so the client
/// here and the app's server build a socket's address, time out and write
/// the same way. `package`: the app's server uses them, nothing outside does.
package enum UnixSocket {
    /// A new stream socket, or -1 with `errno` set.
    package static func make() -> Int32 {
        socket(AF_UNIX, SOCK_STREAM, 0)
    }

    /// The longest path a socket's address holds (103 bytes on macOS),
    /// since the address keeps it with its closing zero.
    package static let maximumPathLength = MemoryLayout.size(ofValue: sockaddr_un().sun_path) - 1

    /// The refusal for a socket path longer than an address holds.
    package static func tooLong(_ path: String) -> String {
        "the socket's path is longer than \(maximumPathLength) bytes, the most a socket's address holds: \(path)"
    }

    /// `path` as a socket address, or nil when it's too long.
    package static func address(_ path: String) -> sockaddr_un? {
        let bytes = Array(path.utf8)
        guard bytes.count <= maximumPathLength else { return nil }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes) }
        return address
    }

    /// `connect(2)` to `address`: 0, or -1 with `errno` set.
    package static func connectSocket(_ descriptor: Int32, to address: sockaddr_un) -> Int32 {
        var address = address
        return withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
    }

    /// `bind(2)` to `address`: 0, or -1 with `errno` set.
    package static func bindSocket(_ descriptor: Int32, to address: sockaddr_un) -> Int32 {
        var address = address
        return withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
    }

    /// Makes each read and write on `descriptor` give up after `seconds`
    /// (`EAGAIN`).
    package static func configure(_ descriptor: Int32, timeout seconds: TimeInterval) {
        let whole = Int(seconds)
        var limit = timeval(tv_sec: whole, tv_usec: .init((seconds - Double(whole)) * 1_000_000))
        let size = socklen_t(MemoryLayout<timeval>.size)
        setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &limit, size)
        setsockopt(descriptor, SOL_SOCKET, SO_SNDTIMEO, &limit, size)
    }

    /// Writes all of `data`. False when the peer went away or a write
    /// timed out. A write to a peer that closed fails instead of raising
    /// `SIGPIPE`, which would end the process: `MSG_NOSIGNAL` on each
    /// write, since macOS refuses `SO_NOSIGPIPE` on a socket whose peer has
    /// already closed.
    package static func writeAll(_ descriptor: Int32, _ data: Data) -> Bool {
        data.withUnsafeBytes { raw -> Bool in
            guard let base = raw.baseAddress else { return true }
            var sent = 0
            while sent < raw.count {
                let wrote = send(descriptor, base + sent, raw.count - sent, Int32(MSG_NOSIGNAL))
                if wrote < 0 {
                    if errno == EINTR { continue }
                    return false
                }
                sent += wrote
            }
            return true
        }
    }

    /// How reading to the end went.
    package enum Read {
        case data(Data)
        /// A read waited longer than the socket's timeout.
        case timedOut
        /// A read failed: the reason, from `errno`.
        case failed(String)
    }

    /// Reads until the peer closes its side (or half-closes it), at most
    /// `limit` bytes.
    package static func readToEnd(_ descriptor: Int32, limit: Int = 8 << 20) -> Read {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 16384)
        while data.count <= limit {
            let count = buffer.withUnsafeMutableBytes { recv(descriptor, $0.baseAddress, $0.count, 0) }
            if count > 0 {
                data.append(contentsOf: buffer[0..<count])
            } else if count == 0 {
                return .data(data)
            } else if errno == EINTR {
                continue
            } else if errno == EAGAIN || errno == EWOULDBLOCK {
                return .timedOut
            } else {
                return .failed(reason())
            }
        }
        return .failed("more than \(limit) bytes")
    }

    /// Closes the writing side, so the peer reads to its end.
    package static func finishWriting(_ descriptor: Int32) {
        shutdown(descriptor, SHUT_WR)
    }

    /// `errno` in words.
    package static func reason(_ code: Int32 = errno) -> String {
        String(cString: strerror(code))
    }
}
