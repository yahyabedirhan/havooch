#if canImport(AppKit)
import AppKit
#endif
import Foundation
import ReviewWire
import Synchronization

/// Starts the app, which `havooch app open` can't ask through the
/// socket since the app isn't running yet, and brings it to the front for
/// `havooch open`. Tests record the launch and the activation.
public protocol AppLaunching: Sendable {
    /// Launches the app with `environment` (empty for a normal launch) set
    /// for it: in the background, or `inFront` of the other apps, as
    /// `havooch open` launches it. Throws a line saying why it couldn't.
    func launch(environment: [String: String], inFront: Bool) throws(AppLaunchFailure)
    /// Brings the running app's process `pid` to the front, as `havooch
    /// open` does after the app opened the video. Returns whether it came.
    func bringToFront(pid: Int32) -> Bool
}

extension AppLaunching {
    /// Launches the app in the background: the agent's terminal keeps the focus.
    public func launch(environment: [String: String]) throws(AppLaunchFailure) {
        try launch(environment: environment, inFront: false)
    }
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
/// app forward unless asked: the agent's terminal keeps the focus.
public struct WorkspaceLauncher: AppLaunching {
    var command: URL?
    var timeout: TimeInterval = 10
    var quitGrace: TimeInterval = 5

    public init(command: URL?) {
        self.command = command
    }

    static func bundle(of command: URL?) -> URL? {
        if let command {
            let bundle = command.resolvingSymlinksInPath()
                .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            if bundle.pathExtension == "app" { return bundle }
        }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: AppIdentity.bundleID)
    }

    public func launch(environment: [String: String], inFront: Bool) throws(AppLaunchFailure) {
        guard let url = Self.bundle(of: command) else {
            throw AppLaunchFailure("\(AppIdentity.appName) isn't installed (no app with the bundle id \(AppIdentity.bundleID)); run `make install`")
        }
        if !inFront { waitWhileRunning() }
        if !inFront, !environment.isEmpty, !Self.running.isEmpty {
            for app in Self.running { app.terminate() }
            waitWhileRunning()
            guard Self.running.isEmpty else {
                throw AppLaunchFailure("a copy of \(AppIdentity.appName) that doesn't answer is still running; quit it, then try again")
            }
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = inFront
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

    /// By the process, not the bundle: two copies of the app (the installed
    /// one and a build) share the bundle id, and only this one is meant.
    public func bringToFront(pid: Int32) -> Bool {
        NSRunningApplication(processIdentifier: pid)?.activate() ?? false
    }

    private static var running: [NSRunningApplication] {
        NSRunningApplication.runningApplications(withBundleIdentifier: AppIdentity.bundleID).filter { !$0.isTerminated }
    }

    private func waitWhileRunning() {
        let deadline = Date().addingTimeInterval(quitGrace)
        while Date() < deadline, !Self.running.isEmpty {
            Thread.sleep(forTimeInterval: 0.1)
        }
    }

    private final class LaunchOutcome: Sendable {
        let error = Mutex<String?>(nil)
    }
}
#else
/// The app is a macOS app: elsewhere the command reaches an app that runs,
/// and never launches one.
public struct WorkspaceLauncher: AppLaunching {
    public init(command: URL?) {}

    public func launch(environment: [String: String], inFront: Bool) throws(AppLaunchFailure) {
        throw AppLaunchFailure("\(AppIdentity.appName) runs only on macOS")
    }

    public func bringToFront(pid: Int32) -> Bool {
        false
    }
}
#endif
