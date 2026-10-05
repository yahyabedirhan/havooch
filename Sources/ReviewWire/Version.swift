/// The versions of this build. The `Makefile` stamps the bundle with `app`.
public enum Version {
    /// The app's version, under semantic versioning. `video-review --version`
    /// prints it.
    public static let app = "0.2.0"

    /// The control protocol's version, a number of its own. A request of
    /// another version is refused with both numbers, never misread. 2 since
    /// 0.1.0: the prototypes spoke 1. 3 since 0.2.0: `thread.show` replaced
    /// `thread.expand`, `state` names `sidebar.thread`, and `screenshot`
    /// takes a `window`.
    public static let controlProtocol = 3
}
