import AppKit
import SwiftUI
import VRLease
import VRWire

/// The app: one window, its menus, and the composition root (`AppDelegate`).
@main
struct VideoReviewApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Window(Identity.appName, id: "main") {
            MainView(model: delegate.model, lease: delegate.lease)
        }
        .defaultSize(width: 1100, height: 720)
        .commands {
            // One window, one video: Open replaces New.
            CommandGroup(replacing: .newItem) {
                Button("Open…") { delegate.model.chooseVideo() }
                    .keyboardShortcut("o")
            }
            // A Command shortcut, so it works wherever the focus is, the
            // comment box included.
            CommandGroup(after: .newItem) {
                Button("Send Comments") { delegate.model.sendBatchForPerson() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(!delegate.model.canSend)
            }
        }
    }
}

/// The composition root: makes the model and the control server, starts
/// the server once the app has launched and stops it when the app quits.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model: AppModel
    /// The lease as the window shows it; the server keeps it current.
    let lease = LeaseIndicator()
    private let server: ControlServer
    private let shortcuts: ShortcutMonitor

    override init() {
        let environment = ProcessInfo.processInfo.environment
        let model = AppModel(environment: environment)
        // Both sockets are in the real support folder, whatever the data's folder.
        let real = SupportFolder.real()
        self.model = model
        server = ControlServer(
            socket: model.isDemo ? ControlSocket.demo(in: real) : ControlSocket.real(in: real),
            model: model,
            screenshotter: Screenshotter(model: model),
            lease: ControlLease(environment: environment, at: Date()),
            indicator: lease,
            quit: { NSApp.terminate(nil) }
        )
        shortcuts = ShortcutMonitor(model: model)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Run from `.build` without a bundle, the app would otherwise have no window or menu.
        NSApp.setActivationPolicy(.regular)
        shortcuts.start()
        do {
            try server.start()
        } catch {
            // The window still works for the person; agents find no socket.
            NSLog("video-review: app control is off: %@", error.description)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        server.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    /// A video opened from the Finder, or dropped on the app's icon.
    func application(_ application: NSApplication, open urls: [URL]) {
        if let video = urls.first { model.openForPerson(video) }
    }
}

/// The window's content: the lease banner while an agent controls the app,
/// then the frame above the transport bar, under the overlay that draws
/// regions and holds the comment box, with the notice for an agent message
/// at its bottom right, and the sidebar on the trailing edge.
struct MainView: View {
    let model: AppModel
    let lease: LeaseIndicator
    @State private var sidebar = true

    var body: some View {
        VStack(spacing: 0) {
            LeaseBanner(indicator: lease)
            ZStack {
                // Black around a video in both appearances, as players do.
                Color.black
                if let video = model.player.video {
                    PlayerSurface(player: model.player.player)
                    RegionOverlay(model: model, video: video)
                } else {
                    EmptyState(model: model)
                        .background(.background)
                }
            }
            // An agent message, briefly, away from the frame's centre.
            .overlay(alignment: .bottomTrailing) {
                if let notice = model.notice {
                    NoticeToast(model: model, notice: notice)
                        .padding(14)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                        .id(notice.id)
                }
            }
            .animation(.easeOut(duration: 0.2), value: model.notice?.id)
            Divider()
            TransportBar(model: model)
        }
        .frame(minWidth: 640, minHeight: 420)
        .inspector(isPresented: $sidebar) {
            Sidebar(model: model)
                .inspectorColumnWidth(min: 240, ideal: 300, max: 440)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                PresencePill(listener: model.listener)
            }
            ToolbarItem(placement: .primaryAction) {
                ContextNote(model: model)
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    sidebar.toggle()
                } label: {
                    Label("Comments", systemImage: "sidebar.trailing")
                }
                .help(sidebar ? "Hide the comments" : "Show the comments")
            }
        }
        .navigationTitle(model.player.video?.url.lastPathComponent ?? Identity.appName)
        .dropDestination(for: URL.self) { urls, _ in
            guard let video = urls.first else { return false }
            model.openForPerson(video)
            return true
        }
        .alert("Video Review", isPresented: Binding(get: { model.failure != nil }, set: { if !$0 { model.failure = nil } })) {
            Button("OK") { model.failure = nil }
        } message: {
            Text(model.failure ?? "")
        }
        .background(WindowReader { model.window = $0 })
    }
}

/// Tells `found` the window the view sits in, once it's in one.
private struct WindowReader: NSViewRepresentable {
    let found: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = WindowReportingView()
        view.found = found
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {}

    private final class WindowReportingView: NSView {
        var found: ((NSWindow?) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            found?(window)
        }
    }
}
