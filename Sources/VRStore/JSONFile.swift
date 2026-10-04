import Foundation

/// One Codable value kept as one JSON file, replaced whole on every write.
enum JSONFile {
    /// The value in the file at `url`, or nil when there's no file.
    static func read<Value: Decodable>(_ type: Value.Type, at url: URL) throws -> Value? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(type, from: Data(contentsOf: url))
    }

    /// Writes `value` at `url`, creating its folder. The file is replaced in
    /// one step, so a reader never sees half of it.
    static func write(_ value: some Encodable, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        try encoder.encode(value).write(to: url, options: .atomic)
    }
}
