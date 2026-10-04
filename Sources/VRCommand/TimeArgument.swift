/// A time in the video as the command line writes it: seconds (`10`,
/// `10.5`), minutes and seconds (`0:10`, `1:02.5`), or hours too (`1:02:03`).
enum TimeArgument {
    /// The time in seconds, or nil when `text` isn't one.
    static func seconds(_ text: String) -> Double? {
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count), let last = parts.last, let seconds = number(last) else { return nil }
        // Alone, the seconds may pass a minute (`90`); under minutes they can't.
        guard parts.count == 1 || seconds < 60 else { return nil }
        var total = seconds
        var unit = 60.0
        for (index, part) in parts.dropLast().reversed().enumerated() {
            guard let whole = wholeNumber(part) else { return nil }
            // Under hours, the minutes can't pass an hour.
            if index == 0, parts.count == 3, whole >= 60 { return nil }
            total += Double(whole) * unit
            unit *= 60
        }
        return total
    }

    /// Digits with at most one point among them: no sign, no exponent.
    private static func number(_ text: Substring) -> Double? {
        guard text.contains(where: \.isASCIIDigit),
              text.allSatisfy({ $0.isASCIIDigit || $0 == "." }),
              text.count(where: { $0 == "." }) <= 1
        else { return nil }
        return Double(text)
    }

    private static func wholeNumber(_ text: Substring) -> Int? {
        guard !text.isEmpty, text.allSatisfy(\.isASCIIDigit) else { return nil }
        return Int(text)
    }
}

private extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
}
