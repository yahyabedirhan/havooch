import AppKit
import ReviewWire
import SwiftUI

/// The app: one window, one video at a time.
@main
struct VideoReviewApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Window(AppIdentity.appName, id: "main") {
            RootView(model: delegate.model)
        }
        // A 16:9 video fills the stage beside the rail with no letterbox.
        .defaultSize(width: 1360, height: 730)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open…") { delegate.model.openFromPanel() }
                    .keyboardShortcut("o")
            }
            PlaybackCommands(model: delegate.model)
        }
    }
}

/// The Playback menu. Its items carry no key equivalents: the player's keys
/// (`Shortcuts`) have no modifier, and a menu would take them from a text
/// field.
private struct PlaybackCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandMenu("Playback") {
            Group {
                Button(model.engine.isPlaying ? "Pause" : "Play") { model.togglePlay() }
                Divider()
                Button("Back 5 Seconds") { model.skip(by: -Shortcuts.skip) }
                Button("Forward 5 Seconds") { model.skip(by: Shortcuts.skip) }
                Button("Previous Frame") { model.step(frames: -1) }
                Button("Next Frame") { model.step(frames: 1) }
            }
            .disabled(model.video == nil)
        }
    }
}

/// Owns what lives as long as the app: the model and the control server.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel(environment: ProcessInfo.processInfo.environment)
    private var server: ControlServer?
    private var termination: (any DispatchSourceSignal)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        quitOnTermination()
        Shortcuts.install(for: model)
        let server = ControlServer(
            socket: ControlSocket.url(in: model.support), app: model, screenshotter: Screenshotter(),
            quit: { NSApp.terminate(nil) }
        )
        do throws(ControlServer.Failure) {
            try server.start()
            self.server = server
        } catch {
            // Another copy already runs on this data: one app per support folder.
            FileHandle.standardError.write(Data("\(AppIdentity.appName): \(error.description)\n".utf8))
            NSApp.terminate(nil)
        }
    }

    /// A `SIGTERM` (`make install` replacing the app) quits as the menu
    /// does, so the socket is removed and no command finds a dead one.
    private func quitOnTermination() {
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler { NSApp.terminate(nil) }
        source.resume()
        termination = source
    }

    func applicationWillTerminate(_ notification: Notification) {
        server?.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
