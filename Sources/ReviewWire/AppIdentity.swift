/// Which build this is. Several prototypes run on one Mac, each with its
/// own app name, bundle id and support folder, so they never replace or
/// reach each other. `variant` is the one setting: the `Makefile` reads the
/// line below, and the real product sets it to "".
public enum AppIdentity {
    public static let variant = "proto-2"

    /// The app's name: `Video Review (proto-2)`, or `Video Review`.
    public static var appName: String {
        variant.isEmpty ? "Video Review" : "Video Review (\(variant))"
    }

    /// The bundle id: `com.yahyabedirhan.video-review.proto-2`, or without
    /// the suffix.
    public static var bundleID: String {
        variant.isEmpty ? "com.yahyabedirhan.video-review" : "com.yahyabedirhan.video-review.\(variant)"
    }

    /// The folder's name under `~/Library/Application Support/`.
    public static var supportFolderName: String { appName }
}
