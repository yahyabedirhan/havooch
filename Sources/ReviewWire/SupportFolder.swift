import Foundation

/// Where the app keeps what it writes: the one definition, so the
/// `havooch` command and the app can't disagree.
public enum SupportFolder {
    /// The variable that moves the support folder elsewhere, which
    /// `havooch app open --demo` launches the app with.
    public static let overrideVariable = "HAVOOCH_SUPPORT_DIR"

    /// The support folder: `HAVOOCH_SUPPORT_DIR` when it's an absolute
    /// path, else `~/Library/Application Support/<the app's name>/`.
    public static func app(environment: [String: String]) -> URL {
        moved(environment: environment)
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent(AppIdentity.supportFolderName, isDirectory: true)
    }

    /// The folder `HAVOOCH_SUPPORT_DIR` moves the app's to, when it's an
    /// absolute path.
    public static func moved(environment: [String: String]) -> URL? {
        guard let override = environment[overrideVariable], override.hasPrefix("/") else { return nil }
        return URL(fileURLWithPath: override, isDirectory: true)
    }

    /// The variable `havooch app open --demo` launches the app with, set
    /// to `1` beside `HAVOOCH_SUPPORT_DIR`: the run is the demo.
    public static let demoRunVariable = "HAVOOCH_DEMO_RUN"

    /// Whether `environment` launches a demo run: `app open --demo` moved
    /// the support folder and marked the launch. A folder moved with no
    /// mark (a check's scratch folder) is a normal run on that folder.
    public static func isDemoRun(environment: [String: String]) -> Bool {
        moved(environment: environment) != nil && environment[demoRunVariable] == "1"
    }
}
