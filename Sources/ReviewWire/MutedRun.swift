import Foundation

/// A run muted for an agent's check: started with
/// `HAVOOCH_MUTED=1`, it plays no sound in any window, whatever level the
/// person left, and keeps that level as it was. `havooch app open --demo`
/// passes the variable on to the app it launches.
public enum MutedRun {
    /// The variable that starts the app muted.
    public static let variable = "HAVOOCH_MUTED"

    /// Whether `environment` starts a muted run: the variable is `1`.
    public static func isMuted(environment: [String: String]) -> Bool {
        environment[variable] == "1"
    }
}
