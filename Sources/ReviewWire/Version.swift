/// The versions of this build. The `Makefile` stamps the bundle with `app`.
public enum Version {
    /// The app's version, under semantic versioning. `havooch --version`
    /// prints it.
    public static let app = "0.4.0"

    /// The control protocol's version, a number of its own. A request of
    /// another version is refused with both numbers, never misread. 2 since
    /// 0.1.0: the prototypes spoke 1. 3 since 0.2.0: `thread.show` replaced
    /// `thread.expand`, `state` names `sidebar.thread`, and `screenshot`
    /// takes a `window`. 4 since the windows: a request names its
    /// `window`, and `window.list`, `window.new` and `window.close` came.
    /// 5 since projects: `project.new` and `project.add` came, and `open`
    /// and `wait` name a `project`, which an older app would not read.
    /// 6 since the thread list by version and the version switcher:
    /// `thread.versions.open`, `thread.versions.close`, `thread.version`,
    /// `version.show`, `version.pick` and `version.close` came, then
    /// compare's `compare.open`, `.pick`, `.set`, `.swap`, `.start` and
    /// `.exit`, which an older app refuses in words as unknown commands.
    public static let controlProtocol = 6
}
