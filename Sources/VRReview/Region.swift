/// A rectangle on the frame, in parts of the frame from 0 to 1, with the
/// origin at the top left. It doesn't know the frame's size in pixels or
/// the window's in points, so it names the same part of the picture
/// whatever size the frame is shown at.
public struct Region: Codable, Equatable, Sendable {
    public let x, y, w, h: Double

    /// How far past the frame's edge a sum may land and still count as on
    /// it: `0.7 + 0.3` isn't exactly 1 in binary.
    private static let slack = 1e-9

    /// Nil unless the rectangle lies inside the frame and has an area.
    public init?(x: Double, y: Double, w: Double, h: Double) {
        guard [x, y, w, h].allSatisfy(\.isFinite), x >= 0, y >= 0, w > 0, h > 0,
              x + w <= 1 + Self.slack, y + h <= 1 + Self.slack
        else { return nil }
        self.x = x
        self.y = y
        self.w = w
        self.h = h
    }

    /// The region with those four numbers, or the review's refusal: for
    /// numbers that come from outside, as `comment add --region` gives them.
    public static func checked(x: Double, y: Double, w: Double, h: Double) throws(ReviewError) -> Region {
        guard let region = Region(x: x, y: y, w: w, h: h) else { throw .regionOutsideFrame }
        return region
    }

    /// The region between two opposite corners, in whatever order they come
    /// and wherever they are: each is first brought onto the frame. Nil when
    /// nothing is left between them. A drag that starts at any corner, or
    /// runs past the frame's edge, becomes a region this way.
    public static func spanning(from one: (x: Double, y: Double), to other: (x: Double, y: Double)) -> Region? {
        func onFrame(_ value: Double) -> Double { value.isFinite ? min(max(0, value), 1) : 0 }
        let left = min(onFrame(one.x), onFrame(other.x)), right = max(onFrame(one.x), onFrame(other.x))
        let top = min(onFrame(one.y), onFrame(other.y)), bottom = max(onFrame(one.y), onFrame(other.y))
        return Region(x: left, y: top, w: right - left, h: bottom - top)
    }

    /// A stored region that isn't inside the frame doesn't read.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let x = try container.decode(Double.self, forKey: .x), y = try container.decode(Double.self, forKey: .y)
        let w = try container.decode(Double.self, forKey: .w), h = try container.decode(Double.self, forKey: .h)
        guard let region = Region(x: x, y: y, w: w, h: h) else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "the region \(x),\(y),\(w),\(h) is outside the frame")
            )
        }
        self = region
    }

    /// The region's pixels in a frame `size` large, origin top left: each
    /// edge at the nearest pixel edge, kept inside the frame, and at least
    /// one pixel each way. This is the rectangle a crop is cut at.
    public func pixels(in size: (width: Int, height: Int)) -> (x: Int, y: Int, width: Int, height: Int) {
        func span(_ start: Double, _ length: Double, _ whole: Int) -> (Int, Int) {
            guard whole > 0 else { return (0, 0) }
            let from = min(max(0, Int((start * Double(whole)).rounded())), whole - 1)
            let to = min(max(from + 1, Int(((start + length) * Double(whole)).rounded())), whole)
            return (from, to - from)
        }
        let (left, width) = span(x, w, size.width)
        let (top, height) = span(y, h, size.height)
        return (left, top, width, height)
    }
}
