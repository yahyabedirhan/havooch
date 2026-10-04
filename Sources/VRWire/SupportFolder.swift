import Foundation

/// Where the app keeps its data and its socket: the one definition, so the
/// `video-review` command and the app can't disagree.
public enum SupportFolder {
    /// The variable that moves the app's data elsewhere, as `video-review
    /// app open --demo` launches the app with.
    public static let overrideVariable = "VIDEO_REVIEW_SUPPORT_DIR"

    /// `~/Library/Application Support/<Identity.supportFolderName>/`: the
    /// person's data, and every run's socket and demo pointer.
    public static func real() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Identity.supportFolderName, isDirectory: true)
    }

    /// The folder `overrideVariable` moves the app's data to, when it's an
    /// absolute path: what makes a run a demo run.
    public static func demo(environment: [String: String]) -> URL? {
        guard let override = environment[overrideVariable], override.hasPrefix("/") else { return nil }
        return URL(fileURLWithPath: override, isDirectory: true)
    }

    /// The folder the app run with `environment` keeps its data in: the
    /// demo folder in a demo run, else the real one.
    public static func current(environment: [String: String]) -> URL {
        demo(environment: environment) ?? real()
    }
}
