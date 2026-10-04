/// The versions of this build. The `Makefile` stamps the bundle with `app`.
public enum Version {
    /// The app's version.
    public static let app = "0.1.0"

    /// The control protocol's version. A request of another version is
    /// refused with both numbers, never misread.
    public static let controlProtocol = 1
}
