import AppKit
import SwiftUI

final class FirstRunWindow: NSObject, NSWindowDelegate {
    private let app: AppModel
    private var made: NSWindow?

    init(app: AppModel) {
        self.app = app
    }

    var window: NSWindow? {
        guard let made, made.isVisible else { return nil }
        return made
    }

    func present(_ showing: Bool) {
        guard showing else {
            made?.close()
            return
        }
        let placed = made != nil
        let window = made ?? make()
        if !placed { place(window) }
        window.makeKeyAndOrderFront(nil)
    }

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
