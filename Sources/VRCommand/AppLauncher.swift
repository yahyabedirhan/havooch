import AppKit
import Foundation
import VRWire

/// Starts the app, which `video-review app open` can't ask through the
/// socket since the app isn't running yet. Tests record the launch.
public protocol AppLaunching: Sendable {
    /// Launches the app at `bundle` (the installed app with this build's
    /// bundle id when nil) without bringing it forward, with `environment`
    /// (empty for the person's data) set for it. Throws a line saying why
    /// it couldn't.
    func launch(bundle: URL?, environment: [String: String]) throws(AppLaunchFailure)
}

/// Why the app couldn't be launched, in words.
public struct AppLaunchFailure: Error, Equatable, Sendable {
    public var reason: String

    public init(_ reason: String) {
        self.reason = reason
    }
}

/// Launches through Launch Services (`NSWorkspace`), without bringing the
/// app forward: the agent's terminal keeps the focus. The only AppKit use
/// on the agent side.
public struct WorkspaceLauncher: AppLaunching {
    /// How long to wait for Launch Services to say the app started.
    var timeout: TimeInterval = 10
    /// How long to wait for a quitting copy of the app to end before
    /// launching. `app open` only launches once nothing answers on the
    /// socket, so a copy still there is quitting.
    var quitGrace: TimeInterval = 5

    public init() {}

    public func launch(bundle: URL?, environment: [String: String]) throws(AppLaunchFailure) {
        guard let url = bundle ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: Identity.bundleID) else {
            throw AppLaunchFailure("no app with the bundle id \(Identity.bundleID) is installed")
        }
        // An app just asked to quit removes its socket before its process
        // ends; Launch Services would hand that process back instead of
        // starting one with this environment, so let it finish first.
        let deadline = Date().addingTimeInterval(quitGrace)
        while Date() < deadline,
              NSRunningApplication.runningApplications(withBundleIdentifier: Identity.bundleID).contains(where: { !$0.isTerminated }) {
            Thread.sleep(forTimeInterval: 0.1)
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.addsToRecentItems = false
        if !environment.isEmpty { configuration.environment = environment }
        let outcome = LaunchOutcome()
        let done = DispatchSemaphore(value: 0)
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
            outcome.error = error.map(\.localizedDescription)
            done.signal()
        }
        guard done.wait(timeout: .now() + timeout) == .success else {
            throw AppLaunchFailure("Launch Services didn't start \(url.path) within \(Int(timeout)) seconds")
        }
        if let error = outcome.error {
            throw AppLaunchFailure("couldn't launch \(url.path): \(error)")
        }
    }

    /// The completion handler's answer, read after the semaphore.
    private final class LaunchOutcome: @unchecked Sendable {
        var error: String?
    }
}
