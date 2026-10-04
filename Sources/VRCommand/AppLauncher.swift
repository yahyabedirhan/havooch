import AppKit
import Foundation

/// Starts the app, which `video-review app open` can't ask through the
/// socket since the app isn't running yet. Tests record the launch.
public protocol AppLaunching: Sendable {
    /// Launches the app `bundleID` in the background, with `environment`
    /// (empty for a normal launch) set for it. Throws a line saying why it
    /// couldn't.
    func launch(bundleID: String, environment: [String: String]) throws(AppLaunchFailure)
}

/// Why the app couldn't be launched, in words.
public struct AppLaunchFailure: Error, Equatable, Sendable {
    public var reason: String

    public init(_ reason: String) {
        self.reason = reason
    }
}

/// Launches through Launch Services (`NSWorkspace`), without bringing the
/// app forward: the agent's terminal keeps the focus.
public struct WorkspaceLauncher: AppLaunching {
    /// How long to wait for Launch Services to say the app started.
    var timeout: TimeInterval = 10
    /// How long to wait for a quitting copy of the app to end before
    /// launching. `app open` only launches once nothing answers on the
    /// socket, so a copy still there is quitting.
    var quitGrace: TimeInterval = 5

    public init() {}

    public func launch(bundleID: String, environment: [String: String]) throws(AppLaunchFailure) {
        guard let url = Self.enclosingApp(of: Bundle.main.executableURL)
            ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        else {
            throw AppLaunchFailure("no app with the bundle id \(bundleID) is installed")
        }
        // An app just asked to quit removes its socket before its process
        // ends; Launch Services would hand that process back instead of
        // starting one with this environment, so let it finish first.
        let deadline = Date().addingTimeInterval(quitGrace)
        while Date() < deadline,
              NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).contains(where: { !$0.isTerminated }) {
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

    /// The app bundle whose `Contents/Helpers` holds the command at
    /// `executable`, or nil when it runs from somewhere else (a build
    /// folder). The command launches the app it shipped in, so a copy of
    /// the same bundle id elsewhere on the disk is never picked instead.
    static func enclosingApp(of executable: URL?) -> URL? {
        guard let executable = executable?.resolvingSymlinksInPath() else { return nil }
        let helpers = executable.deletingLastPathComponent()
        let contents = helpers.deletingLastPathComponent()
        let app = contents.deletingLastPathComponent()
        guard helpers.lastPathComponent == "Helpers", contents.lastPathComponent == "Contents",
              app.pathExtension == "app" else { return nil }
        return app
    }

    /// The completion handler's answer, read after the semaphore.
    private final class LaunchOutcome: @unchecked Sendable {
        var error: String?
    }
}
