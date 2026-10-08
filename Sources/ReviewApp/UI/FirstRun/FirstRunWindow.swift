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
        let window = made ?? make()
        if !window.isVisible { window.center() }
        window.makeKeyAndOrderFront(nil)
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
