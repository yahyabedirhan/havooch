import Foundation

/// A time in a video as people write it: seconds (`90`, `12.5`), or
/// `mm:ss` and `h:mm:ss` with an optional fraction (`1:30`, `0:01:30.5`).
public enum TimeCode {
    /// The seconds `text` names, or nil when it isn't a time: empty,
    /// negative, not a number, more than three parts, or minutes or seconds
    /// of 60 or more after a colon.
    public static func seconds(_ text: String) -> Double? {
        let parts = text.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard (1...3).contains(parts.count), let last = parts.last, let seconds = number(last, fraction: true) else {
            return nil
        }
        if parts.count == 1 { return seconds }
        var total = seconds
        guard seconds < 60 else { return nil }
        var unit = 60.0
        for (index, part) in parts.dropLast().reversed().enumerated() {
            guard let value = number(part, fraction: false) else { return nil }
            // Minutes under an hours part stay below 60; the first part is free.
            if index == 0, parts.count == 3, value >= 60 { return nil }
            total += value * unit
            unit *= 60
        }
        return total
    }

    /// `seconds` as `m:ss` (`0:10`), `h:mm:ss` from an hour on, with the
    /// fraction to the millisecond when there is one (`0:12.5`).
    public static func text(_ seconds: Double) -> String {
        let milliseconds = Int((max(seconds, 0) * 1000).rounded())
        let (whole, fraction) = milliseconds.quotientAndRemainder(dividingBy: 1000)
        let (minutes, second) = whole.quotientAndRemainder(dividingBy: 60)
        var text = minutes >= 60
            ? "\(minutes / 60):\(pad(minutes % 60)):\(pad(second))"
            : "\(minutes):\(pad(second))"
        if fraction > 0 {
            var digits = String(format: "%03d", fraction)
            while digits.hasSuffix("0") { digits.removeLast() }
            text += "." + digits
        }
        return text
    }

    /// `text` as a number of digits, with one decimal point when `fraction`
    /// allows it: no sign, no exponent, no spaces.
    private static func number(_ text: String, fraction: Bool) -> Double? {
        guard !text.isEmpty, text.first != ".", text.last != "." else { return nil }
        let points = text.filter { $0 == "." }.count
        guard points <= (fraction ? 1 : 0), text.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == ".") }) else { return nil }
        return Double(text)
    }

    private static func pad(_ value: Int) -> String {
        value < 10 ? "0\(value)" : "\(value)"
    }
}
