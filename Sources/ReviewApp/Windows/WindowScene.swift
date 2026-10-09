import AppKit
import ReviewWire
import SwiftUI

/// One player window's scene: the `WindowGroup`'s content for a target
/// (ADR 0003). As it appears it takes the `WindowModel` made for it, or a
/// new empty one, and its scene value follows what the window holds. It
/// hands SwiftUI's `openWindow` to the registry, so the app can open a
/// window from a control command, and tells the app which AppKit window
/// shows the model.
struct WindowScene: View {
    /// The scene's id in `HavoochApp`.
    static let sceneID = "player"

    let app: AppModel
    /// What the window holds, as SwiftUI keeps it for the scene.
    @Binding var target: WindowTarget?
    /// The lease as the header's agent-control icon draws it, and its Stop.
    let lease: AgentControlIcon
    let stopLease: () -> Void

    @State private var model: WindowModel?
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            if let model {
                RootView(model: model, lease: lease, stopLease: stopLease)
                    .background(WindowReader { app.attach($0, to: model) })
                    .focusedSceneValue(\.playerWindow, model)
                    .onChange(of: model.target, initial: true) { _, held in
                        if target != held { target = held }
                    }
            } else {
                Color.clear.frame(minWidth: Metrics.stageMinimumWidth, minHeight: Metrics.windowMinimumHeight)
            }
        }
        .onAppear {
            let action = openWindow
            app.windows.openScene = { target in
                if let target {
                    action(id: Self.sceneID, value: target)
                } else {
                    action(id: Self.sceneID)
                }
            }
            if model == nil { model = app.sceneAppeared(target: target) }
        }
    }
}

/// The player window that has the keys, for the menus: File › Close Video
/// and the Playback menu act on it.
extension FocusedValues {
    var playerWindow: WindowModel? {
        get { self[PlayerWindowKey.self] }
        set { self[PlayerWindowKey.self] = newValue }
    }
}

private struct PlayerWindowKey: FocusedValueKey {
    typealias Value = WindowModel
}

/// Tells `found` the AppKit window a view is in, once it's in one.
private struct WindowReader: NSViewRepresentable {
    let found: (NSWindow) -> Void

    func makeNSView(context: Context) -> ReaderView {
        let view = ReaderView()
        view.found = found
        return view
    }

    func updateNSView(_ view: ReaderView, context: Context) {
        view.found = found
        if let window = view.window { found(window) }
    }

    final class ReaderView: NSView {
        var found: ((NSWindow) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { found?(window) }
        }
    }
}
