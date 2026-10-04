import Foundation
import VRWire

/// The parsing every command shares.
enum Arguments {
    static let jsonFlag = "--json"

    /// Whether the arguments ask for the command's usage.
    static func asksForHelp(_ arguments: [String]) -> Bool {
        arguments.contains("--help") || arguments.contains("-h")
    }

    /// A time as the command line gives it: seconds (`10`, `10.5`), `mm:ss`
    /// (`0:10`, `1:02.5`) or `h:mm:ss`. Nil when it doesn't read: a part
    /// that isn't a number, a negative one, seconds or minutes of 60 or more
    /// after a colon, or a fraction anywhere but in the seconds.
    static func time(_ text: String) -> Double? {
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count) else { return nil }
        var total = 0.0
        for (index, part) in parts.enumerated() {
            // Digits and one dot only: `Double` would also read "1e3", "nan" and "+5".
            guard !part.isEmpty, part.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == ".") }),
                  let value = Double(part) else { return nil }
            let isLast = index == parts.count - 1
            if !isLast, part.contains(".") { return nil }
            if index > 0, value >= 60 { return nil }
            total = total * 60 + value
        }
        return total
    }

    /// A region as the command line gives it: `x,y,w,h`, four numbers. Nil
    /// when it doesn't read. Whether they are inside the frame is the app's
    /// to say.
    static func region(_ text: String) -> ControlRequest.WireRegion? {
        let parts = text.split(separator: ",", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        var numbers: [Double] = []
        for part in parts {
            let digits = part.trimmingCharacters(in: .whitespaces)
            // Digits and one dot only, as for a time.
            guard !digits.isEmpty, digits.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == ".") }),
                  let value = Double(digits) else { return nil }
            numbers.append(value)
        }
        return ControlRequest.WireRegion(x: numbers[0], y: numbers[1], w: numbers[2], h: numbers[3])
    }

    /// `path` as a file, taken against `directory` when it's relative.
    static func absolute(_ path: String, in directory: URL) -> URL {
        URL(fileURLWithPath: path, relativeTo: directory).standardizedFileURL
    }
}
