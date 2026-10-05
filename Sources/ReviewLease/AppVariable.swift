/// The app's environment variables are named `HAVOOCH_*`. Before the app
/// was renamed (docs/adr/0002) they were `VIDEO_REVIEW_*`, and agents' setups
/// and scripts may still export those: a variable's earlier name is read when
/// its own isn't set. What the app and the command write is always the new
/// name.
public enum AppVariable {
    /// The prefix of every variable's name.
    public static let prefix = "HAVOOCH_"
    /// The prefix the variables had before the rename.
    public static let earlierPrefix = "VIDEO_REVIEW_"

    /// The value of `name`, a `HAVOOCH_*` variable, in `environment`; when
    /// it isn't set, the value of its `VIDEO_REVIEW_*` name.
    public static func value(_ name: String, in environment: [String: String]) -> String? {
        if let value = environment[name] { return value }
        return earlierName(of: name).flatMap { environment[$0] }
    }

    /// `VIDEO_REVIEW_SUPPORT_DIR` for `HAVOOCH_SUPPORT_DIR`; nil for a name
    /// without the prefix.
    public static func earlierName(of name: String) -> String? {
        guard name.hasPrefix(prefix) else { return nil }
        return earlierPrefix + name.dropFirst(prefix.count)
    }
}
