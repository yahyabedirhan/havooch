import AppKit
import SwiftUI
import VRWire

/// The app: one window on one video at a time.
@main
struct VideoReviewApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Window(AppIdentity.name, id: "main") {
            MainWindow(model: AppServices.shared.model, controller: AppServices.shared.player)
                // The lease's banner tops the window, whatever it shows.
                .safeAreaInset(edge: .top, spacing: 0) {
                    LeaseBanner(indicator: AppServices.shared.leaseIndicator) { AppServices.shared.server.stopLease() }
                }
        }
        .defaultSize(width: 1100, height: 700)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open…") {
                    if let url = VideoPicker.choose() { AppServices.shared.model.openByPerson(url) }
                }
                .keyboardShortcut("o")
            }
        }
    }
}

/// The app's life: app control listens while it runs, and a video opened
/// from the Finder opens in the window.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppServices.shared.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppServices.shared.stop()
    }

    /// One window: closing it ends the app, so the socket never outlives
    /// what it controls.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        if let url = urls.first { AppServices.shared.model.openByPerson(url) }
    }
}
