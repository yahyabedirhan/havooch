import ReviewLease

/// Which app this is: its name, its bundle id and its support folder. The
/// app and the `video-review` command both link it, so they can't disagree.
/// The `Makefile` names and stamps the bundle with the same values.
public enum AppIdentity {
    /// `Video Review`. The lease's refusals name the app too, and the lease
    /// depends on nothing, so the name is defined there.
    public static let appName = ControlLease.appName

    public static let bundleID = "com.yahyabedirhan.video-review"

    /// The folder's name under `~/Library/Application Support/`.
    public static let supportFolderName = appName
}
