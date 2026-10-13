import AppKit
import ReviewLease
import ReviewWire
import SwiftUI

/// The app: any number of windows, each holding one video or no video, and
/// Settings (⌘,).
@main
struct HavoochApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        // One scene per window, its value what the window holds; a window
        // that holds nothing shows the home screen.
        WindowGroup(AppIdentity.appName, id: WindowScene.sceneID, for: WindowTarget.self) { $target in
            WindowScene(app: delegate.model, target: $target, lease: delegate.lease) { delegate.stopLease() }
                .modifier(SettingsOpener(settings: delegate.settings))
        }
        // A 16:9 video fills the stage beside the sidebar with no letterbox.
        .defaultSize(width: 1360, height: 730)
        // A launch opens no video: one empty window shows home.
        .restorationBehavior(.disabled)
        .commands {
            FileCommands(app: delegate.model)
            CloseVideoCommand()
            AboutCommand()
            PlaybackCommands()
            ThemeMenu(model: delegate.model)
        }
        SwiftUI.Settings {
            SettingsView(model: delegate.model)
        }
    }

}

/// File › New Window, Cmd+N: a new empty window that shows home. File ›
/// Open…, Cmd+O: a video for the window that has the keys, or for a new
/// window with none.
private struct FileCommands: Commands {
    let app: AppModel
    @FocusedValue(\.playerWindow) private var window

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Window") { app.newWindow() }
                .keyboardShortcut("n")
            Button("Open…") { app.openFromPanel(from: window) }
                .keyboardShortcut("o")
        }
    }
}

/// The Playback menu, on the window that has the keys. Its playback items
/// carry no key equivalents: the player's keys (`Shortcuts`) have no
/// modifier, and a menu would take them from a text field. Send Messages
/// shows Cmd+Return, the key `Shortcuts` acts on first; both go through
/// `WindowModel.send`. Mute and Unmute is the M key's.
private struct PlaybackCommands: Commands {
    @FocusedValue(\.playerWindow) private var model

    var body: some Commands {
        CommandMenu("Playback") {
            Group {
                Button(model?.engine.isPlaying == true ? "Pause" : "Play") { model?.togglePlay() }
                Divider()
                Button("Back 5 Seconds") { model?.skip(by: -Shortcuts.skip) }
                Button("Forward 5 Seconds") { model?.skip(by: Shortcuts.skip) }
                Button("Previous Frame") { model?.step(frames: -1) }
                Button("Next Frame") { model?.step(frames: 1) }
                Divider()
                Button("Previous Marker") { model?.jumpToMarker(forward: false) }
                Button("Next Marker") { model?.jumpToMarker(forward: true) }
                Divider()
                Button("Add Message") { model?.startDraft() }
            }
            .disabled(model?.video == nil)
            // The app's sound, which M mutes and unmutes too; a run muted
            // for an agent's check can't change it.
            Button(model?.app.sound.isMuted == true ? "Unmute" : "Mute") { model?.app.toggleMuteForPerson() }
                .disabled(model == nil || model?.app.sound.isMutedForCheck == true)
            // The one item with a key: Cmd+Return is no key a text field takes.
            Button("Send Messages") { model?.send() }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(model?.canSend != true)
        }
    }
}

/// File > Close Video, Shift+Cmd+W: the window that has the keys goes
/// home, as the Havooch mark in its header does (`WindowModel.goHome`).
/// Cmd+W stays the window's Close.
private struct CloseVideoCommand: Commands {
    @FocusedValue(\.playerWindow) private var model

    var body: some Commands {
        CommandGroup(after: .saveItem) {
            Button("Close Video") { model?.goHomeForPerson() }
                .keyboardShortcut("w", modifiers: [.command, .shift])
                .disabled(model?.video == nil)
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
    /// The first-run window, shown on the first launch and by `first-run show`.
    private(set) lazy var firstRunWindow = FirstRunWindow(app: model)
    private var server: ControlServer?
    private var termination: (any DispatchSourceSignal)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        quitOnTermination()
        // `havooch open` has put its window forward; the app comes to the front.
        model.bringToFront = { _ in NSApp.activate() }
        model.watchWindows()
        Shortcuts.install(for: model)
        OutsideClicks.install(for: model)
        model.themes.followSystemAppearance()
        let server = ControlServer(
            // The socket stays on the folder the run started on, also during
            // an in-app demo; the listener's requests go to the data the run is on.
            socket: ControlSocket.url(in: model.launchSupport), app: model, listeners: { [model] in model.listeners },
            screenshotter: Screenshotter(indicator: lease, settings: settings, firstRun: firstRunWindow),
            // A relaunch (`app open --demo` on a running app) hands the operator's lease over.
            lease: ControlLease(environment: ProcessInfo.processInfo.environment, at: Date()),
            indicator: lease,
            quit: { NSApp.terminate(nil) }
        )
        do throws(SocketListener.Failure) {
            try server.start()
            self.server = server
            // A save of config.toml applies at once, and a theme file
            // edited by hand shows at once.
            model.config.startWatching()
            model.themes.startWatching()
            // A launch opens no video: its one window shows home. The first
            // launch shows the first-run window in front of it.
            let firstRun = firstRunWindow
            model.firstRun.present = { [weak firstRun] showing in firstRun?.present(showing) }
            model.showFirstRunOnFirstLaunch()
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
        // The person may have linked the command or installed the skill in
        // a terminal meanwhile: setup reads the disk again, never polling.
        model.setup.probe()
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.savePositions()
        server?.stop()
    }

    /// Closing the last window leaves the app running in the Dock, with no
    /// window. Cmd+Q quits.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Finder's Open With, a drop on the Dock icon and `open -a Havooch
    /// <file>`: the same open as `havooch open`.
    func application(_ application: NSApplication, open urls: [URL]) {
        model.openFromFinder(urls.filter(\.isFileURL))
    }

    /// A click on the Dock icon with no window open: a new empty window
    /// that shows home. With a window open, or minimized, the app comes
    /// forward as usual.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag, model.windows.windows.isEmpty, model.windows.openScene != nil {
            model.newWindow()
            return false
        }
        return true
    }
}
