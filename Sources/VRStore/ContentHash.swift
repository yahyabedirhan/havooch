import CryptoKit
import Foundation

/// A video file's hash, which names the video in the store: SHA-256 over the
/// file's byte count, its first 4 MiB and its last 4 MiB, as lowercase hex.
/// A file of 8 MiB or less is hashed whole. A renamed or moved copy has the
/// same hash.
public enum ContentHash {
    /// How much of each end of a large file is read.
    static let edge = 4 << 20

    public static func of(_ file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        let size = try handle.seekToEnd()
        try handle.seek(toOffset: 0)
        var hasher = SHA256()
        hasher.update(data: Data(String(size).utf8))
        if size <= UInt64(2 * edge) {
            hasher.update(data: try handle.readToEnd() ?? Data())
        } else {
            hasher.update(data: try handle.read(upToCount: edge) ?? Data())
            try handle.seek(toOffset: size - UInt64(edge))
            hasher.update(data: try handle.readToEnd() ?? Data())
        }
        return hasher.finalize().map { byte in
            let hex = String(byte, radix: 16)
            return byte < 16 ? "0" + hex : hex
        }.joined()
    }
}
