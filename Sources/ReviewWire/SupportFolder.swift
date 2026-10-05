import Foundation
import ReviewLease

/// Where the app keeps what it writes: the one definition, so the
/// `havooch` command and the app can't disagree.
public enum SupportFolder {
    /// The variable that moves the support folder elsewhere, which
    /// `havooch app open --demo` launches the app with. Its earlier name,
    /// `VIDEO_REVIEW_SUPPORT_DIR`, is read when it isn't set (`AppVariable`).
    public static let overrideVariable = "HAVOOCH_SUPPORT_DIR"

    /// The user's `~/Library/Application Support/`.
    public static var applicationSupport: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    /// The support folder: `HAVOOCH_SUPPORT_DIR` when it's an absolute
    /// path, else `<applicationSupport>/<the app's name>/`.
    public static func app(environment: [String: String], applicationSupport: URL = applicationSupport) -> URL {
        moved(environment: environment)
            ?? applicationSupport.appendingPathComponent(AppIdentity.supportFolderName, isDirectory: true)
    }

    /// The folder `HAVOOCH_SUPPORT_DIR` moves the app's to, when it's an
    /// absolute path: what makes a run a demo run.
    public static func moved(environment: [String: String]) -> URL? {
        guard let override = AppVariable.value(overrideVariable, in: environment), override.hasPrefix("/") else { return nil }
        return URL(fileURLWithPath: override, isDirectory: true)
    }
}
