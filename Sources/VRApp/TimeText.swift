/// A time in the video as text.
enum TimeText {
    /// To the millisecond, as command replies print it: `0:10.000`,
    /// `1:02:03.500`.
    static func exact(_ seconds: Double) -> String {
        let milliseconds = Int((max(0, seconds) * 1000).rounded())
        let whole = clock(milliseconds / 1000)
        let fraction = String(milliseconds % 1000)
        return whole + "." + String(repeating: "0", count: 3 - fraction.count) + fraction
    }

    /// To the second, as the transport bar shows it: `0:10`.
    static func short(_ seconds: Double) -> String {
        clock(Int(max(0, seconds)))
    }

    /// The time rounded to the millisecond, as `state` reports it.
    static func rounded(_ seconds: Double) -> Double {
        (seconds * 1000).rounded() / 1000
    }

    /// `m:ss`, or `h:mm:ss` from an hour on.
    private static func clock(_ seconds: Int) -> String {
        let hours = seconds / 3600, minutes = seconds % 3600 / 60, rest = seconds % 60
        let padded = { (value: Int) in value < 10 ? "0\(value)" : "\(value)" }
        return hours > 0 ? "\(hours):\(padded(minutes)):\(padded(rest))" : "\(minutes):\(padded(rest))"
    }
}
