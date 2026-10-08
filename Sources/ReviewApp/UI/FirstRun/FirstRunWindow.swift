import AppKit
import SwiftUI

/// The first-run window on screen (H1): an AppKit window of its own, beside
/// the player windows, made the first time it shows and kept for the run.
/// `AppModel.firstRun.present` shows and closes it. Its close button only
/// closes it: unlike Skip Setup, it doesn't make the first run done, so the
/// next launch shows it again.
final class FirstRunWindow: NSObject, NSWindowDelegate {
    private let app: AppModel
    private var made: NSWindow?

    init(app: AppModel) {
        self.app = app
    }

    /// The window while it's on screen, for `screenshot --window first-run`.
    var window: NSWindow? {
        guard let made, made.isVisible else { return nil }
        return made
    }

    /// Puts the window on screen, in front, or takes it off.
    func present(_ showing: Bool) {
        guard showing else {
            made?.close()
            return
        }
        let placed = made != nil
        let window = made ?? make()
        // Placed once, the first time it shows: a later show in the same
        // run keeps where the person moved it.
        if !placed { place(window) }
        window.makeKeyAndOrderFront(nil)
    }

    /// Sizes `window` to what its view settles on, then centers it over the
    /// player window in front, else on the screen. `center()` alone measured
    /// the size the window was made with, before the hosting view resized it,
    /// and centered it on the screen, not over the player window.
    private func place(_ window: NSWindow) {
        if let view = window.contentView {
            view.layoutSubtreeIfNeeded()
            let fitting = view.fittingSize
            if fitting.width > 0, fitting.height > 0 { window.setContentSize(fitting) }
        }
        let player = (app.windows.key?.nsWindow).flatMap { $0.isVisible ? $0 : nil }
            ?? app.windows.windows.lazy.compactMap(\.nsWindow).first(where: \.isVisible)
        guard let screen = player?.screen ?? NSScreen.main else {
            window.center()
            return
        }
        window.setFrame(Self.frame(of: window.frame.size, over: player?.frame, on: screen.visibleFrame), display: false)
    }

    /// A frame of `size` centered over `player`, else over `screen`, moved
    /// in where it would leave `screen`.
    static func frame(of size: CGSize, over player: CGRect?, on screen: CGRect) -> CGRect {
        let around = player ?? screen
        var origin = CGPoint(x: (around.midX - size.width / 2).rounded(), y: (around.midY - size.height / 2).rounded())
        origin.x = min(max(origin.x, screen.minX), screen.maxX - size.width)
        origin.y = min(max(origin.y, screen.minY), screen.maxY - size.height)
        return CGRect(origin: origin, size: size)
    }

    private func make() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: FirstRunView.size.width, height: FirstRunView.size.height),
            styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.title = "Welcome to Havooch"
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = true
        window.identifier = NSUserInterfaceItemIdentifier("first-run")
        window.contentView = NSHostingView(rootView: FirstRunView(app: app))
        window.delegate = self
        made = window
        return window
    }

    func windowWillClose(_ notification: Notification) {
        app.firstRun.closedByPerson()
    }
}
