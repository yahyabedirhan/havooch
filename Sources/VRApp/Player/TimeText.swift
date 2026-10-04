import Foundation

/// A time in the video as text: `0:10` in the window, `0:10.000` in the
/// command's output; hours only when there are some.
enum TimeText {
    /// `m:ss`, or `h:mm:ss`.
    static func short(_ seconds: Double) -> String {
        clock(Int(max(0, seconds)))
    }

    /// `m:ss.mmm`, or `h:mm:ss.mmm`.
    static func precise(_ seconds: Double) -> String {
        let milliseconds = Int((max(0, seconds) * 1000).rounded())
        return clock(milliseconds / 1000) + String(format: ".%03d", milliseconds % 1000)
    }

    private static func clock(_ whole: Int) -> String {
        let (hours, minutes, seconds) = (whole / 3600, whole / 60 % 60, whole % 60)
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
    }
}
