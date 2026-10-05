import AppKit
import ReviewLease
import ReviewWire
import SwiftUI

/// The app: one window, one video at a time, and Settings (⌘,).
@main
struct HavoochApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Window(AppIdentity.appName, id: "main") {
            RootView(model: delegate.model, lease: delegate.lease) { delegate.stopLease() }
                .modifier(SettingsOpener(settings: delegate.settings))
        }
        // A 16:9 video fills the stage beside the sidebar with no letterbox.
        .defaultSize(width: 1360, height: 730)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open…") { delegate.model.openFromPanel() }
                    .keyboardShortcut("o")
            }
            AboutCommand()
            PlaybackCommands(model: delegate.model)
            ThemeMenu(model: delegate.model)
        }
        SwiftUI.Settings {
            SettingsView(model: delegate.model)
        }
    }

    /// The line the log gets about the earlier support folder; nil when
    /// there was nothing to do.
    static func describe(_ outcome: EarlierSupportFolder.Outcome) -> String? {
        switch outcome {
        case .nothingToDo:
            return nil
        case .earlierAppRuns:
            return "\(EarlierSupportFolder.name) runs, so its data stays in its folder until the next launch"
        case let .moved(moved, kept):
            let from = "~/Library/Application Support/\(EarlierSupportFolder.name)"
            var line = "moved \(moved.count) item(s) from \(from)"
            if !kept.isEmpty { line += "; kept there, since the support folder has them or they didn't move: \(kept.joined(separator: ", "))" }
            return line
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
    let model: AppModel = {
        let environment = ProcessInfo.processInfo.environment
        // Before the model reads the support folder: an update from the
        // app's earlier name keeps the person's data.
        let earlierRuns = !NSRunningApplication.runningApplications(withBundleIdentifier: EarlierSupportFolder.bundleID).isEmpty
        let outcome = EarlierSupportFolder.move(environment: environment, earlierAppRuns: earlierRuns)
        if let line = HavoochApp.describe(outcome) {
            FileHandle.standardError.write(Data("\(AppIdentity.appName): \(line)\n".utf8))
        }
        return AppModel(environment: environment)
    }()
    /// The lease as the agent-control icon draws it; the control server writes it.
    let lease = AgentControlIcon()
    /// The Settings window, for app control's screenshots of it.
    let settings = SettingsWindow()
    private var server: ControlServer?
    private var termination: (any DispatchSourceSignal)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        quitOnTermination()
        Shortcuts.install(for: model)
        OutsideClicks.install(for: model)
        model.themes.followSystemAppearance()
        let server = ControlServer(
            socket: ControlSocket.url(in: model.support), app: model, listeners: model.listeners,
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
            // Only the one copy that has the socket touches the data.
            server.ready = Task { await model.openAtLaunch(environment: ProcessInfo.processInfo.environment) }
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

    func applicationWillTerminate(_ notification: Notification) {
        server?.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
