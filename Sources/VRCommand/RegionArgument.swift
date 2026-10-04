import VRWire

/// A region as the command line writes it: `x,y,w,h`, four numbers that are
/// parts of the frame from 0 to 1, with the origin at the top left
/// (`0.48,0.3,0.28,0.12`). Only the shape is judged here. Whether the
/// rectangle lies inside the frame is the app's rule, so its refusal reads
/// the same for every caller.
enum RegionArgument {
    /// The four numbers, or nil when `text` isn't four of them.
    static func region(_ text: String) -> WireRegion? {
        let parts = text.split(separator: ",", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        let numbers = parts.compactMap(number)
        guard numbers.count == 4 else { return nil }
        return WireRegion(x: numbers[0], y: numbers[1], w: numbers[2], h: numbers[3])
    }

    /// Digits with at most one point among them, after at most one minus
    /// sign: no blank space, no exponent, no `nan`, no `inf`.
    private static func number(_ text: Substring) -> Double? {
        let digits = text.hasPrefix("-") ? text.dropFirst() : text
        guard digits.contains(where: { $0.isASCII && $0.isNumber }),
              digits.allSatisfy({ ($0.isASCII && $0.isNumber) || $0 == "." }),
              digits.count(where: { $0 == "." }) <= 1
        else { return nil }
        return Double(text)
    }
}
