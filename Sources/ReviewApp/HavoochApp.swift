import AppKit
import ReviewLease
import ReviewWire
import SwiftUI

/// The app: one window, one video at a time, and Settings (⌘,).
@main
struct HavoochApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Window(AppIdentity.appName, id: PlayerWindow.sceneID) {
            RootView(model: delegate.model, lease: delegate.lease) { delegate.stopLease() }
                .modifier(SettingsOpener(settings: delegate.settings))
                .modifier(PlayerWindowOpener(window: delegate.window))
        }
        // A 16:9 video fills the stage beside the sidebar with no letterbox.
        .defaultSize(width: 1360, height: 730)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open…") { delegate.model.openFromPanel() }
                    .keyboardShortcut("o")
            }
            CloseVideoCommand(model: delegate.model)
            AboutCommand()
            PlaybackCommands(model: delegate.model)
            ThemeMenu(model: delegate.model)
        }
        SwiftUI.Settings {
            SettingsView(model: delegate.model)
        }
    }

}

/// The Playback menu. Its playback items carry no key equivalents: the
/// player's keys (`Shortcuts`) have no modifier, and a menu would take them
/// from a text field. Send Messages shows Cmd+Return, the key `Shortcuts`
/// acts on first; both go through `AppModel.send`.
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
                Divider()
                Button("Previous Marker") { model.jumpToMarker(forward: false) }
                Button("Next Marker") { model.jumpToMarker(forward: true) }
                Divider()
                Button("Add Message") { model.startDraft() }
            }
            .disabled(model.video == nil)
            // The one item with a key: Cmd+Return is no key a text field takes.
            Button("Send Messages") { model.send() }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!model.canSend)
        }
    }
}

/// File > Close Video, Shift+Cmd+W: home, as the Havooch mark in the
/// header goes (`AppModel.goHome`). Cmd+W stays the window's Close.
private struct CloseVideoCommand: Commands {
    let model: AppModel

    var body: some Commands {
        CommandGroup(after: .saveItem) {
            Button("Close Video") { model.goHomeForPerson() }
                .keyboardShortcut("w", modifiers: [.command, .shift])
                .disabled(model.video == nil)
        }
    }
}

/// View > Theme: follow the system appearance, or pin one theme. The
/// same choice as Settings and `havooch theme set`.
private struct ThemeMenu: Commands {
    let model: AppModel

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            ThemePicker(model: model)
        }
    }
}

/// Owns what lives as long as the app: the model and the control server.
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel(environment: ProcessInfo.processInfo.environment)
    /// The lease as the agent-control icon draws it; the control server writes it.
    let lease = AgentControlIcon()
    /// The Settings window, for app control's screenshots of it.
    let settings = SettingsWindow()
    /// The player's window, which closes while the app runs on.
    let window = PlayerWindow()
    private var server: ControlServer?
    private var termination: (any DispatchSourceSignal)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        quitOnTermination()
        model.showWindow = { [window] in window.show() }
        window.watchClose { [model] in model.windowClosed() }
        Shortcuts.install(for: model)
        OutsideClicks.install(for: model)
        model.themes.followSystemAppearance()
        let server = ControlServer(
            // The socket stays on the folder the run started on, also during
            // an in-app demo; the listener's requests go to the data the run is on.
            socket: ControlSocket.url(in: model.launchSupport), app: model, listeners: { [model] in model.listeners },
            screenshotter: Screenshotter(indicator: lease, settings: settings),
            // A relaunch (`app open --demo` on a running app) hands the operator's lease over.
            lease: ControlLease(environment: ProcessInfo.processInfo.environment, at: Date()),
            indicator: lease,
            quit: { NSApp.terminate(nil) }
        )
        do throws(SocketListener.Failure) {
            try server.start()
            self.server = server
            // A theme file or settings.json edited by hand shows at once.
            model.themes.startWatching()
            // A launch opens no video: the window shows home.
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

    /// The agent-control icon's Stop: the person takes the app back from the agent.
    func stopLease() {
        server?.stopLease()
    }

    /// The person may have moved or deleted a recent video in Finder
    /// meanwhile: the home screen reads the list again.
    func applicationDidBecomeActive(_ notification: Notification) {
        model.refreshRecents()
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.savePosition()
        server?.stop()
    }

    /// Cmd+W closes the window and the app stays in the Dock, with its
    /// model: the video, the playhead and the sidebar. Cmd+Q quits.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// A click on the Dock icon with the window closed shows it again, as
    /// it was. Before the window has been on screen once, SwiftUI's own
    /// reopen shows it.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        flag || !window.show()
    }
}
