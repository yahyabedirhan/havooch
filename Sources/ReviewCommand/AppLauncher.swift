#if canImport(AppKit)
import AppKit
#endif
import Foundation
import ReviewWire
import Synchronization

/// Starts the app, which `havooch app open` can't ask through the
/// socket since the app isn't running yet. Tests record the launch.
public protocol AppLaunching: Sendable {
    /// Launches the app in the background, with `environment` (empty for a
    /// normal launch) set for it. Throws a line saying why it couldn't.
    func launch(environment: [String: String]) throws(AppLaunchFailure)
}

/// Why the app couldn't be launched, in words.
public struct AppLaunchFailure: Error, Equatable, Sendable {
    public var reason: String

    public init(_ reason: String) {
        self.reason = reason
    }
}

#if canImport(AppKit)
/// Launches through Launch Services (`NSWorkspace`), without bringing the
/// app forward: the agent's terminal keeps the focus.
public struct WorkspaceLauncher: AppLaunching {
    /// The `havooch` executable that runs, when it's known.
    var command: URL?
    /// How long to wait for Launch Services to say the app started.
    var timeout: TimeInterval = 10
    /// How long to wait for a copy of the app to end before launching.
    var quitGrace: TimeInterval = 5

    public init(command: URL?) {
        self.command = command
    }

    /// The app to launch: the bundle this command ships in
    /// (`<app>/Contents/Helpers/havooch`), so each build's command
    /// starts its own app; else the installed app with this build's bundle
    /// id.
    static func bundle(of command: URL?) -> URL? {
        if let command {
            let bundle = command.resolvingSymlinksInPath()
                .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            if bundle.pathExtension == "app" { return bundle }
        }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: AppIdentity.bundleID)
    }

    public func launch(environment: [String: String]) throws(AppLaunchFailure) {
        guard let url = Self.bundle(of: command) else {
            throw AppLaunchFailure("\(AppIdentity.appName) isn't installed (no app with the bundle id \(AppIdentity.bundleID)); run `make install`")
        }
        // An app just asked to quit removes its socket before its process
        // ends; Launch Services would hand that process back instead of
        // starting one with this environment, so let it finish first.
        waitWhileRunning()
        // A copy still there isn't quitting: it's starting (`make install`
        // just opened it) or it runs without app control. Launch Services
        // would hand it back as it is, on its own data, so when the launch
        // needs an environment that copy is asked to quit first.
        if !environment.isEmpty, !Self.running.isEmpty {
            for app in Self.running { app.terminate() }
            waitWhileRunning()
            guard Self.running.isEmpty else {
                throw AppLaunchFailure("a copy of \(AppIdentity.appName) that doesn't answer is still running; quit it, then try again")
            }
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.addsToRecentItems = false
        if !environment.isEmpty { configuration.environment = environment }
        let outcome = LaunchOutcome()
        let done = DispatchSemaphore(value: 0)
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
            outcome.error.withLock { $0 = error.map(\.localizedDescription) }
            done.signal()
        }
        guard done.wait(timeout: .now() + timeout) == .success else {
            throw AppLaunchFailure("Launch Services didn't start \(url.path) within \(Int(timeout)) seconds")
        }
        if let error = outcome.error.withLock({ $0 }) {
            throw AppLaunchFailure("couldn't launch \(url.path): \(error)")
        }
    }

    /// The copies of this build's app that run.
    private static var running: [NSRunningApplication] {
        NSRunningApplication.runningApplications(withBundleIdentifier: AppIdentity.bundleID).filter { !$0.isTerminated }
    }

    /// Waits until no copy of the app runs, `quitGrace` at most.
    private func waitWhileRunning() {
        let deadline = Date().addingTimeInterval(quitGrace)
        while Date() < deadline, !Self.running.isEmpty {
            Thread.sleep(forTimeInterval: 0.1)
        }
    }

    /// The completion handler's answer, read after the semaphore. Launch
    /// Services calls the handler on its own queue, so the answer crosses
    /// threads behind a lock.
    private final class LaunchOutcome: Sendable {
        let error = Mutex<String?>(nil)
    }
}
#else
/// The app is a macOS app: elsewhere the command reaches an app that runs,
/// and never launches one.
public struct WorkspaceLauncher: AppLaunching {
    public init(command: URL?) {}

    public func launch(environment: [String: String]) throws(AppLaunchFailure) {
        throw AppLaunchFailure("\(AppIdentity.appName) runs only on macOS")
    }
}
#endif
