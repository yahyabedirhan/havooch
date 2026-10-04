import Foundation

/// What one JSON file of the store holds: its content beside the version
/// of the form it was written in.
protocol StoredFile: Codable {
    /// The version this build writes, and the only one it reads.
    static var current: Int { get }
    var version: Int { get }
}

extension StoredFile {
    /// The file at `url` as this build reads it. A file that doesn't read,
    /// that another version wrote, or that `valid` turns down is moved
    /// aside (`review.json` becomes `review.unreadable.json`) and counts
    /// as none, so nothing is written over it.
    static func read(at url: URL, valid: (Self) -> Bool = { _ in true }) -> Self? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        if let data = try? Data(contentsOf: url), let kept = try? JSONDecoder().decode(Self.self, from: data),
           kept.version == current, valid(kept) {
            return kept
        }
        let aside = url.deletingPathExtension().appendingPathExtension("unreadable.json")
        try? FileManager.default.removeItem(at: aside)
        try? FileManager.default.moveItem(at: url, to: aside)
        return nil
    }

    /// Writes the file whole at `url`, making the folders above it: a
    /// reader finds the file as it was or as it is now, never a part of it.
    func write(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(self)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}
