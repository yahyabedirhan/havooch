#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation

/// A rectangle on the video's frame, in normalized coordinates: 0..1 across
/// and down the frame, from its top left corner. It means the same part of
/// the picture at any window size and for any frame size.
public struct Region: Codable, Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let w: Double
    public let h: Double

    /// How far past the frame's edge a sum may land from rounding alone.
    private static let slack = 1e-9

    /// Refused when the rectangle isn't inside the frame, or has no area.
    public init(x: Double, y: Double, w: Double, h: Double) throws(ReviewRefusal) {
        let inside = [x, y, w, h].allSatisfy(\.isFinite)
            && x >= 0 && y >= 0 && w > 0 && h > 0
            && x + w <= 1 + Self.slack && y + h <= 1 + Self.slack
        guard inside else {
            throw ReviewRefusal(
                "the region \(Self.text(x)),\(Self.text(y)),\(Self.text(w)),\(Self.text(h)) isn't inside the frame: "
                    + "x,y,w,h are parts of the frame from 0 to 1, with w and h above 0, x + w and y + h at most 1"
            )
        }
        self.x = x
        self.y = y
        self.w = w
        self.h = h
    }

    /// The region as `x,y,w,h`, the way `--region` takes it.
    public var text: String {
        [x, y, w, h].map(Self.text).joined(separator: ",")
    }

    /// The pixels of a frame of `size` the region covers, from the frame's
    /// top left: whole pixels, rounded outward so nothing pointed at is cut,
    /// and kept inside the frame.
    public func pixelRect(in size: CGSize) -> CGRect {
        let left = Self.whole(x * size.width).rounded(.down)
        let top = Self.whole(y * size.height).rounded(.down)
        let right = min(size.width, Self.whole((x + w) * size.width).rounded(.up))
        let bottom = min(size.height, Self.whole((y + h) * size.height).rounded(.up))
        return CGRect(x: left, y: top, width: max(1, right - left), height: max(1, bottom - top))
    }

    /// A pixel edge that is whole but for rounding, made whole: 0.3 × 1920
    /// is 576, not a hair under or over it, which would add a pixel.
    private static func whole(_ edge: Double) -> Double {
        let nearest = edge.rounded()
        return abs(edge - nearest) < 1e-6 ? nearest : edge
    }

    /// A part without a trailing `.0`: `0`, `0.25`, `1`.
    private static func text(_ value: Double) -> String {
        value == value.rounded() && abs(value) < 1e15 ? String(Int(value)) : String(value)
    }
}
