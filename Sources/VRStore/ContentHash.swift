import CryptoKit
import Foundation

/// The hash that names a video by what's in it, so a renamed or moved copy
/// is the same video.
public enum ContentHash {
    /// How much of a large file each of its three samples reads: 1 MiB.
    static let sample: UInt64 = 1 << 20

    /// SHA-256 over the file's size and its bytes: all of them when the
    /// file is three samples long or less, else three samples (its start,
    /// its middle and its end), so a large video is named at once. 64 hex
    /// digits.
    public static func of(_ file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        let size = try handle.seekToEnd()
        var hasher = SHA256()
        withUnsafeBytes(of: size.bigEndian) { hasher.update(bufferPointer: $0) }
        let whole = size <= 3 * sample
        for offset in whole ? [0] : [0, (size - sample) / 2, size - sample] {
            try handle.seek(toOffset: offset)
            hasher.update(data: try handle.read(upToCount: Int(whole ? size : sample)) ?? Data())
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
