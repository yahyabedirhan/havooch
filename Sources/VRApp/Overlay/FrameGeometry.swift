import CoreGraphics
import VRReview

/// Where the frame sits in the view that shows it, and the one place that
/// turns the view's points into parts of the frame and back. The frame is
/// fitted whole into the view and centred, as the player's layer shows it,
/// so a wider view has bars at the sides and a taller one above and below.
/// Points have their origin at the view's top left, as a region has its
/// origin at the frame's.
struct FrameGeometry: Equatable {
    /// The frame's size. Only its shape matters here.
    let frame: CGSize
    /// The view's size, in points.
    let view: CGSize

    /// Where the frame is in the view. Empty when either has no area.
    var frameRect: CGRect {
        guard frame.width > 0, frame.height > 0, view.width > 0, view.height > 0 else { return .zero }
        // The side that fills the view is the view's own, to the last digit.
        let size = view.width * frame.height <= view.height * frame.width
            ? CGSize(width: view.width, height: view.width * frame.height / frame.width)
            : CGSize(width: view.height * frame.width / frame.height, height: view.height)
        return CGRect(x: (view.width - size.width) / 2, y: (view.height - size.height) / 2, width: size.width, height: size.height)
    }

    /// The region between two points of the view, which are opposite
    /// corners in any order. What lies outside the frame is left out; nil
    /// when nothing of the frame is between them.
    func region(from one: CGPoint, to other: CGPoint) -> Region? {
        let rect = frameRect
        guard rect.width > 0, rect.height > 0 else { return nil }
        func part(_ point: CGPoint) -> (x: Double, y: Double) {
            (Double((point.x - rect.minX) / rect.width), Double((point.y - rect.minY) / rect.height))
        }
        return Region.spanning(from: part(one), to: part(other))
    }

    /// Where `region` is in the view, at the view's size now.
    func rect(of region: Region) -> CGRect {
        let rect = frameRect
        return CGRect(
            x: rect.minX + CGFloat(region.x) * rect.width, y: rect.minY + CGFloat(region.y) * rect.height,
            width: CGFloat(region.w) * rect.width, height: CGFloat(region.h) * rect.height
        )
    }

    /// Where a box of `size` goes to sit next to `rect` and stay whole in
    /// the view: to its right, else to its left, else below it, else above
    /// it, `gap` away and never nearer than `margin` to the view's edge.
    /// When no side has the room, it goes as near to the right of `rect` as
    /// the view allows, over it.
    func origin(ofBox size: CGSize, beside rect: CGRect, gap: CGFloat = 12, margin: CGFloat = 8) -> CGPoint {
        // The farthest a box may start and still end inside the margin.
        let lastX = max(margin, view.width - margin - size.width), lastY = max(margin, view.height - margin - size.height)
        func within(_ value: CGFloat, _ last: CGFloat) -> CGFloat { min(max(margin, value), last) }
        let top = within(rect.minY, lastY), left = within(rect.minX, lastX)
        if rect.maxX + gap <= lastX { return CGPoint(x: rect.maxX + gap, y: top) }
        if rect.minX - gap - size.width >= margin { return CGPoint(x: rect.minX - gap - size.width, y: top) }
        if rect.maxY + gap <= lastY { return CGPoint(x: left, y: rect.maxY + gap) }
        if rect.minY - gap - size.height >= margin { return CGPoint(x: left, y: rect.minY - gap - size.height) }
        return CGPoint(x: within(rect.maxX + gap, lastX), y: top)
    }
}
