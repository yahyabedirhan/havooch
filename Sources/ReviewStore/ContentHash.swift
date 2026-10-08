// CryptoKit exists on Apple platforms only; elsewhere the module builds without the hash.
#if canImport(CryptoKit)
import CryptoKit
import Foundation
import Synchronization

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

/// The content hashes worked out in this run, by path, each kept as long as
/// its file keeps the size and the modification time it was hashed at. A
/// video opened again (`havooch open` on a file already seen) skips reading
/// the whole file; a file written over gets a new hash.
public final class ContentHashCache: Sendable {
    /// What a hash was worked out from: the file's size and modification time.
    private struct Stamp: Equatable {
        var size: Int
        var modified: Date
    }

    private let hashes = Mutex<[String: (stamp: Stamp, hash: String)]>([:])
    private let hash: @Sendable (URL) -> String?

    /// `hash` works a file's hash out; tests count its calls.
    public init(hash: @escaping @Sendable (URL) -> String? = { ContentHash.of($0) }) {
        self.hash = hash
    }

    /// The hash of the file at `url`: the kept one while the file's size
    /// and modification time are those it was hashed at, else worked out
    /// and kept. Nil when the file can't be read.
    public func of(_ url: URL) -> String? {
        let path = url.standardizedFileURL.path
        guard let stamp = Self.stamp(of: path) else { return hash(url) }
        if let kept = hashes.withLock({ $0[path] }), kept.stamp == stamp { return kept.hash }
        guard let worked = hash(url) else { return nil }
        hashes.withLock { $0[path] = (stamp, worked) }
        return worked
    }

    private static func stamp(of path: String) -> Stamp? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attributes[.size] as? Int, let modified = attributes[.modificationDate] as? Date
        else { return nil }
        return Stamp(size: size, modified: modified)
    }
}
#endif
