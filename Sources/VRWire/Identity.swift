/// Which build this is. The app and the `video-review` command both link
/// it, so they can't disagree about the bundle or the support folder; the
/// `Makefile` reads the `variant` and `version` lines below with `sed` to
/// name and stamp the bundle.
public enum Identity {
    /// The one build setting. "proto-1" for this prototype; "" for the real product.
    public static let variant = "proto-1"
    public static let version = "0.1.0"

    /// `Video Review (proto-1)`, or `Video Review` for the real product.
    public static var appName: String {
        variant.isEmpty ? "Video Review" : "Video Review (\(variant))"
    }

    /// `com.yahyabedirhan.video-review.proto-1`, or without the suffix.
    public static var bundleID: String {
        variant.isEmpty ? "com.yahyabedirhan.video-review" : "com.yahyabedirhan.video-review.\(variant)"
    }

    /// The folder's name under `~/Library/Application Support/`.
    public static var supportFolderName: String { appName }
}
