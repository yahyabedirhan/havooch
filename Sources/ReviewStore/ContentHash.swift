import CryptoKit
import Foundation

/// A video's identity: the SHA-256 of the whole file, as 64 hex digits. A
/// renamed or moved copy has the same hash.
public enum ContentHash {
    /// The hash of the file at `url`, read in chunks so a large video never
    /// sits in memory. Nil when the file can't be read.
    public static func of(_ url: URL) -> String? {
        guard let file = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? file.close() }
        var hasher = SHA256()
        while true {
            let chunk: Data?
            do {
                chunk = try file.read(upToCount: chunkSize)
            } catch {
                return nil
            }
            // At the file's end there is no chunk.
            guard let chunk, !chunk.isEmpty else { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static let chunkSize = 4 << 20
}
