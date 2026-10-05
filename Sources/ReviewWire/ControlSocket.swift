import Foundation

/// Where app control's socket is: `control.sock` in the app's support
/// folder (`SupportFolder.app`), the user's own (mode 0600), there only
/// while the app runs.
public enum ControlSocket {
    public static let fileName = "control.sock"

    /// The socket the app listens on, in its support folder `support`.
    public static func url(in support: URL) -> URL {
        support.appendingPathComponent(fileName, isDirectory: false)
    }

    /// The socket the `video-review` command asks the running app through,
    /// given the support folder it knows. While `app open --demo` left a
    /// `DemoPointer` there and the demo's socket is there, it's the demo's:
    /// so agents reach a demo run with no variable to repeat. Otherwise (no
    /// demo, or a demo that quit) it's the folder's own, so a normal app
    /// started meanwhile is still found.
    public static func locate(support: URL) -> URL {
        if let demo = DemoPointer.recorded(in: support) {
            let socket = url(in: demo)
            if FileManager.default.fileExists(atPath: socket.path) { return socket }
        }
        return url(in: support)
    }
}
