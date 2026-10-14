import AppKit
import ReviewLease
import ReviewWire
import SwiftUI

@main
struct HavoochApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup(AppIdentity.appName, id: WindowScene.sceneID, for: WindowTarget.self) { $target in
            WindowScene(app: delegate.model, target: $target, lease: delegate.lease) { delegate.stopLease() }
                .modifier(SettingsOpener(settings: delegate.settings))
        }
        .defaultSize(width: 1360, height: 730)
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
            Button(model?.app.sound.isMuted == true ? "Unmute" : "Mute") { model?.app.toggleMuteForPerson() }
                .disabled(model == nil || model?.app.sound.isMutedForCheck == true)
            Button("Send Messages") { model?.send() }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(model?.canSend != true)
        }
    }
}

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

private struct ThemeMenu: Commands {
    let model: AppModel

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            ThemePicker(model: model)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel(environment: ProcessInfo.processInfo.environment)
    let lease = AgentControlIcon()
    let settings = SettingsWindow()
    private(set) lazy var firstRunWindow = FirstRunWindow(app: model)
    private var server: ControlServer?
    private var termination: (any DispatchSourceSignal)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        quitOnTermination()
        model.bringToFront = { _ in NSApp.activate() }
        model.watchWindows()
        Shortcuts.install(for: model)
        OutsideClicks.install(for: model)
        model.themes.followSystemAppearance()
        let server = ControlServer(
            socket: ControlSocket.url(in: model.launchSupport), app: model, listeners: { [model] in model.listeners },
            screenshotter: Screenshotter(indicator: lease, settings: settings, firstRun: firstRunWindow),
            lease: ControlLease(environment: ProcessInfo.processInfo.environment, at: Date()),
            indicator: lease,
            quit: { NSApp.terminate(nil) }
        )
        do throws(SocketListener.Failure) {
            try server.start()
            self.server = server
            model.config.startWatching()
            model.themes.startWatching()
            let firstRun = firstRunWindow
            model.firstRun.present = { [weak firstRun] showing in firstRun?.present(showing) }
            model.showFirstRunOnFirstLaunch()
        } catch {
            FileHandle.standardError.write(Data("\(AppIdentity.appName): \(error.description)\n".utf8))
            NSApp.terminate(nil)
        }
    }

    private func quitOnTermination() {
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler { NSApp.terminate(nil) }
        source.resume()
        termination = source
    }

    func stopLease() {
        server?.stopLease()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        model.refreshRecents()
        model.setup.probe()
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.savePositions()
        server?.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        model.openFromFinder(urls.filter(\.isFileURL))
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag, model.windows.windows.isEmpty, model.windows.openScene != nil {
            model.newWindow()
            return false
        }
        return true
    }
}
