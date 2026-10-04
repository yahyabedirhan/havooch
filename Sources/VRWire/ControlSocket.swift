import Foundation

/// Where app control's sockets are. Both are in the real support folder,
/// the user's own (mode 0600), there only while the app runs: `control.sock`
/// for the app on the person's data, `demo.sock` for a demo run. A demo run
/// keeps its data in the demo folder but never its socket: a socket's path
/// holds 103 bytes, and a demo folder inside a worktree goes past that.
public enum ControlSocket {
    public static let realName = "control.sock"
    public static let demoName = "demo.sock"

    /// The socket of the app on the person's data.
    public static func real(in support: URL) -> URL {
        support.appendingPathComponent(realName, isDirectory: false)
    }

    /// The socket of a demo run.
    public static func demo(in support: URL) -> URL {
        support.appendingPathComponent(demoName, isDirectory: false)
    }

    /// The socket the `video-review` command asks the running app through,
    /// given the real support folder. While `app open --demo` left a
    /// `DemoPointer` there and the demo's socket is there, it's the demo's:
    /// so agents reach a demo run with no variable to repeat. Otherwise (no
    /// demo, or a demo that quit) it's the real one, so the person's app
    /// started meanwhile is still found.
    public static func locate(support: URL) -> URL {
        let demo = demo(in: support)
        if DemoPointer.recorded(in: support) != nil, FileManager.default.fileExists(atPath: demo.path) {
            return demo
        }
        return real(in: support)
    }
}

/// The note `video-review app open --demo` leaves in the real support
/// folder, naming the demo run's folder. Plain `app open` removes it. With
/// `demo.sock`, it's the only thing a demo run puts outside its folder.
///
/// One JSON file, `demo.json`. It fails safe: a file that's missing,
/// doesn't read, comes from a newer build or names a relative path reads as
/// no demo.
public enum DemoPointer {
    public static let fileName = "demo.json"
    public static let currentVersion = 1

    /// The demo folder the pointer in `support` names, if any.
    public static func recorded(in support: URL) -> URL? {
        guard let data = try? Data(contentsOf: url(in: support)),
              let file = try? JSONDecoder().decode(File.self, from: data),
              file.version <= currentVersion,
              file.support.hasPrefix("/")
        else { return nil }
        return URL(fileURLWithPath: file.support, isDirectory: true)
    }

    /// Points the command at the demo run on `demo`, from the real support
    /// folder `support`.
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
    //     { "support": "/Users/me/repo/.scratch/demo", "version": 1 }
    private struct File: Codable {
        var version: Int
        var support: String
    }
}
