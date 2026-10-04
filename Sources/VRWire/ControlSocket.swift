import Foundation

/// Where app control's socket is: `control.sock` in the app's support
/// folder, the user's own (mode 0600), there only while the app runs.
public enum ControlSocket {
    public static let fileName = "control.sock"

    /// The socket the app listens on, in its support folder `support`.
    public static func url(in support: URL) -> URL {
        support.appendingPathComponent(fileName, isDirectory: false)
    }

    /// The socket the `video-review` command asks the running app through,
    /// given the normal support folder. While `app open --demo` left a
    /// `DemoPointer` there and the demo's socket is there, it's the demo's:
    /// so agents reach a demo run with no variable to repeat. Otherwise (no
    /// demo, or a demo that quit) it's the folder's own, so a normal app
    /// started meanwhile is still found.
    public static func locate(support: URL) -> URL {
        if let demo = DemoPointer.recorded(in: support) {
            let socket = url(in: demo.supportFolder)
            if FileManager.default.fileExists(atPath: socket.path) { return socket }
        }
        return url(in: support)
    }
}

/// The note `video-review app open --demo` leaves in the normal support
/// folder, naming the demo run's support folder and its demo folder, so the
/// command finds the demo's socket (`ControlSocket.locate`). Plain `app
/// open` removes it.
///
/// One JSON file, `demo.json`. It fails safe: a file that's missing, doesn't
/// read, comes from a newer build or names a relative path reads as no demo.
///
///     { "folder": "/Users/me/repo/fixtures/sample", "support": "/Users/me/Library/…/d-1a2b3c4d", "version": 1 }
public struct DemoPointer: Codable, Equatable, Sendable {
    public static let fileName = "demo.json"
    public static let currentVersion = 1

    public var version: Int
    /// The demo run's support folder: its socket and its data.
    public var support: String
    /// The demo folder the run was opened on: its videos and sidecars.
    public var folder: String

    public init(support: URL, folder: URL) {
        self.version = Self.currentVersion
        self.support = support.path
        self.folder = folder.path
    }

    public var supportFolder: URL { URL(fileURLWithPath: support, isDirectory: true) }

    /// The support folder of a demo run on `folder`: inside the normal
    /// support folder, named by a hash of the demo folder's path. So the
    /// demo folder itself is never written to, two demo folders never share
    /// data, and the socket's path stays short enough for its address.
    public static func supportFolder(forDemo folder: URL, in support: URL) -> URL {
        // FNV-1a over the path's bytes: stable across runs and builds.
        var hash: UInt32 = 2_166_136_261
        for byte in folder.standardizedFileURL.path.utf8 {
            hash ^= UInt32(byte)
            hash = hash &* 16_777_619
        }
        let hex = String(hash, radix: 16)
        let name = "d-" + String(repeating: "0", count: 8 - hex.count) + hex
        return support.appendingPathComponent(name, isDirectory: true)
    }

    /// The pointer in `support`, if any.
    public static func recorded(in support: URL) -> DemoPointer? {
        guard let data = try? Data(contentsOf: url(in: support)),
              let pointer = try? JSONDecoder().decode(DemoPointer.self, from: data),
              pointer.version <= currentVersion,
              pointer.support.hasPrefix("/"), pointer.folder.hasPrefix("/")
        else { return nil }
        return pointer
    }

    /// Writes this pointer in the normal support folder `support`.
    public func record(in support: URL) throws {
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(self).write(to: Self.url(in: support), options: .atomic)
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
}
