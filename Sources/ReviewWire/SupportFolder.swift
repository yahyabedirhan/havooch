import Foundation

/// Where the app keeps what it writes: the one definition, so the
/// `video-review` command and the app can't disagree.
public enum SupportFolder {
    /// The variable that moves the support folder elsewhere, which
    /// `video-review app open --demo` launches the app with.
    public static let overrideVariable = "VIDEO_REVIEW_SUPPORT_DIR"

    /// The support folder: `VIDEO_REVIEW_SUPPORT_DIR` when it's an absolute
    /// path, else `~/Library/Application Support/<the app's name>/`.
    public static func app(environment: [String: String]) -> URL {
        moved(environment: environment)
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent(AppIdentity.supportFolderName, isDirectory: true)
    }

    /// The folder `VIDEO_REVIEW_SUPPORT_DIR` moves the app's to, when it's
    /// an absolute path: what makes a run a demo run.
    public static func moved(environment: [String: String]) -> URL? {
        guard let override = environment[overrideVariable], override.hasPrefix("/") else { return nil }
        return URL(fileURLWithPath: override, isDirectory: true)
    }
}
