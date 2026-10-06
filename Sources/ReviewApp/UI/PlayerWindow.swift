import AppKit
import SwiftUI

/// The player's window, which closes while the app keeps running: shown
/// again from the Dock icon or by a control command that opens a video
/// (`AppModel.showWindow`), and watched for its close, which pauses the
/// video (`AppModel.windowClosed`).
final class PlayerWindow {
    /// The scene's id in `HavoochApp`.
    static let sceneID = "main"

    /// Opens the window; set once it has been on screen (`PlayerWindowOpener`).
    var open: (() -> Void)?
    private var closing: (any NSObjectProtocol)?

    /// The player's window while it's on screen: the titled window the app
    /// shows that isn't a panel or Settings.
    static var window: NSWindow? {
        NSApp.windows.first { $0.isVisible && isPlayer($0) }
    }

    /// Whether `window` is the player's window.
    static func isPlayer(_ window: NSWindow) -> Bool {
        window.styleMask.contains(.titled) && !(window is NSPanel) && !SettingsWindow.isSettings(window)
    }

    /// Shows the window when it's closed. Returns whether it could: false
    /// before the window has been on screen once.
    @discardableResult
    func show() -> Bool {
        guard Self.window == nil else { return true }
        guard let open else { return false }
        open()
        return true
    }

    /// Calls `closed` each time the player's window closes.
    func watchClose(_ closed: @escaping @MainActor () -> Void) {
        closing = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: nil, queue: .main
        ) { notification in
            guard let window = notification.object as? NSWindow else { return }
            MainActor.assumeIsolated {
                if Self.isPlayer(window) { closed() }
            }
        }
    }
}

/// Hands SwiftUI's `openWindow` to `PlayerWindow`, from a view in the
/// player's window.
struct PlayerWindowOpener: ViewModifier {
    let window: PlayerWindow
    @Environment(\.openWindow) private var openWindow

    func body(content: Content) -> some View {
        content.onAppear {
            let action = openWindow
            window.open = { action(id: PlayerWindow.sceneID) }
        }
    }
}
