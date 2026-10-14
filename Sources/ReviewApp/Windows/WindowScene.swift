import AppKit
import ReviewWire
import SwiftUI

struct WindowScene: View {
    static let sceneID = "player"

    let app: AppModel
    @Binding var target: WindowTarget?
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

extension FocusedValues {
    var playerWindow: WindowModel? {
        get { self[PlayerWindowKey.self] }
        set { self[PlayerWindowKey.self] = newValue }
    }
}

private struct PlayerWindowKey: FocusedValueKey {
    typealias Value = WindowModel
}

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
