import Foundation

/// The note `video-review app open --demo` leaves in the normal support
/// folder, naming the demo run's support folder, so later commands find the
/// demo's socket (`ControlSocket.locate`). Plain `app open` removes it. It's
/// the only file a demo run writes outside its folder.
///
/// One JSON file, `demo.json`. It fails safe: a file that's missing, doesn't
/// read, comes from a newer build or names a relative path reads as no demo.
public enum DemoPointer {
    public static let fileName = "demo.json"
    public static let currentVersion = 1

    /// The demo's support folder the pointer in `support` names, if any.
    public static func recorded(in support: URL) -> URL? {
        guard let data = try? Data(contentsOf: url(in: support)),
              let file = try? JSONDecoder().decode(File.self, from: data),
              file.version <= currentVersion,
              file.support.hasPrefix("/")
        else { return nil }
        return URL(fileURLWithPath: file.support, isDirectory: true)
    }

    /// Points the command at `demo`, the demo run's support folder, from
    /// the normal support folder `support`.
    public static func record(_ demo: URL, in support: URL) throws {
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(File(version: currentVersion, support: demo.path)).write(to: url(in: support), options: .atomic)
    }

    /// Removes the pointer in `support`; nothing to do when there's none.
    public static func remove(in support: URL) throws {
        let file = url(in: support)
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        try FileManager.default.removeItem(at: file)
    }

    /// `demo.json` in `support`.
    public static func url(in support: URL) -> URL {
        support.appendingPathComponent(fileName, isDirectory: false)
    }

    // `demo.json`:
    //
    //     { "support": "/Users/me/demo", "version": 1 }
    private struct File: Codable {
        var version: Int
        var support: String
    }
}
