import Foundation

/// Which build this is. The app's name, its bundle id and its support folder
/// all come from `variant`, so several prototypes run on one Mac without
/// reaching each other, and the real product drops the suffix by setting it
/// to "". The `Makefile` reads `variant` and `version` from this file.
public enum AppIdentity {
    /// The one build setting. "" for the real product.
    public static let variant = "proto-3"
    public static let version = "0.1.0"

    /// The command's name, the same in every build.
    public static let command = "video-review"

    /// The app's name, which is also its bundle folder's and its support
    /// folder's: `Video Review (proto-3)`, or `Video Review`.
    public static var name: String { name(variant: variant) }

    /// The app's bundle id: `com.yahyabedirhan.video-review.proto-3`, or
    /// without the suffix.
    public static var bundleID: String { bundleID(variant: variant) }

    /// The version as the command and the app print it: `0.1.0 (proto-3)`.
    public static var versionText: String {
        variant.isEmpty ? version : "\(version) (\(variant))"
    }

    static func name(variant: String) -> String {
        variant.isEmpty ? "Video Review" : "Video Review (\(variant))"
    }

    static func bundleID(variant: String) -> String {
        variant.isEmpty ? "com.yahyabedirhan.video-review" : "com.yahyabedirhan.video-review.\(variant)"
    }

    /// The variable that moves the support folder: a demo run's app is
    /// launched with it, and tests point the command at a folder of theirs.
    public static let supportVariable = "VIDEO_REVIEW_SUPPORT_DIR"
    /// The variable a demo run's app reads its demo folder from.
    public static let demoVariable = "VIDEO_REVIEW_DEMO_DIR"

    /// The support folder: `supportVariable` when it names an absolute
    /// path, else `~/Library/Application Support/<name>/`.
    public static func supportFolder(
        variables: [String: String] = [:],
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        if let override = variables[supportVariable], override.hasPrefix("/") {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return home
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
    }
}
