#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif
import Foundation

package enum UnixSocket {
    package static func make() -> Int32 {
        #if canImport(Glibc)
        socket(AF_UNIX, Int32(SOCK_STREAM.rawValue), 0)
        #else
        socket(AF_UNIX, SOCK_STREAM, 0)
        #endif
    }

    package static let maximumPathLength = MemoryLayout.size(ofValue: sockaddr_un().sun_path) - 1

    package static func tooLong(_ path: String) -> String {
        "the socket's path is longer than \(maximumPathLength) bytes, the most a socket's address holds: \(path)"
    }

    package static func address(_ path: String) -> sockaddr_un? {
        if let address = plainAddress(path) { return address }
        let url = URL(fileURLWithPath: path)
        guard let link = shortLink(to: url.deletingLastPathComponent().path) else { return nil }
        return plainAddress(link + "/" + url.lastPathComponent)
    }

    private static func plainAddress(_ path: String) -> sockaddr_un? {
        let bytes = Array(path.utf8)
        guard bytes.count <= maximumPathLength else { return nil }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        #if canImport(Darwin)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        #endif
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes) }
        return address
    }

    private static func shortLink(to folder: String) -> String? {
        guard let temporary = userTemporaryFolder() else { return nil }
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in folder.utf8 { hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01b3 }
        let link = temporary + (temporary.hasSuffix("/") ? "" : "/") + "havooch-" + String(hash, radix: 16)
        func pointsThere() -> Bool {
            (try? FileManager.default.destinationOfSymbolicLink(atPath: link)) == folder
        }
        if pointsThere() { return link }
        unlink(link)
        return symlink(folder, link) == 0 || pointsThere() ? link : nil
    }

    /// The user's own temporary folder: on macOS the per-user one, which
    /// `TMPDIR` may not name in every process; elsewhere `TMPDIR` or `/tmp`.
    private static func userTemporaryFolder() -> String? {
        #if canImport(Darwin)
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        guard confstr(_CS_DARWIN_USER_TEMP_DIR, &buffer, buffer.count) > 0 else { return nil }
        return String(decoding: buffer.prefix { $0 != 0 }.map(UInt8.init(bitPattern:)), as: UTF8.self)
        #else
        return NSTemporaryDirectory()
        #endif
    }

    package static func connectSocket(_ descriptor: Int32, to address: sockaddr_un) -> Int32 {
        var address = address
        return withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
    }

    package static func bindSocket(_ descriptor: Int32, to address: sockaddr_un) -> Int32 {
        var address = address
        return withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
    }

    package static func configure(_ descriptor: Int32, timeout seconds: TimeInterval?) {
        let seconds = seconds ?? 0
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
        let flags = Int32(MSG_NOSIGNAL)
        return data.withUnsafeBytes { raw -> Bool in
            guard let base = raw.baseAddress else { return true }
            var sent = 0
            while sent < raw.count {
                let wrote = send(descriptor, base + sent, raw.count - sent, flags)
                if wrote < 0 {
                    if errno == EINTR { continue }
                    return false
                }
                sent += wrote
            }
            return true
        }
    }

    package enum Read {
        case data(Data)
        case timedOut
        case failed(String)
    }

    package static func readToEnd(_ descriptor: Int32, limit: Int = 8 << 20) -> Read {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
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

    package static func finishWriting(_ descriptor: Int32) {
        shutdown(descriptor, Int32(SHUT_WR))
    }

    package static func reason(_ code: Int32 = errno) -> String {
        String(cString: strerror(code))
    }
}
