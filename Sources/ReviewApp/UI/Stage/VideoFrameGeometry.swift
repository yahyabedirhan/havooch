import CoreGraphics
import ReviewCore

/// Where the video's picture is on the stage, and the way between the
/// stage's points and a region's normalized frame coordinates. A region is
/// kept as fractions of the frame, so it's on the same part of the picture
/// at any window size.
struct VideoFrameGeometry: Equatable {
    /// The picture inside the stage: the video fitted whole, centred, with
    /// the letterbox around it.
    let frame: CGRect

    /// The picture of a video `video` in size on a stage `stage` in size.
    /// With no size yet, the picture is taken to fill the stage.
    init(stage: CGSize, video: CGSize) {
        guard video.width > 0, video.height > 0, stage.width > 0, stage.height > 0 else {
            frame = CGRect(origin: .zero, size: stage)
            return
        }
        let scale = min(stage.width / video.width, stage.height / video.height)
        let size = CGSize(width: video.width * scale, height: video.height * scale)
        frame = CGRect(
            x: (stage.width - size.width) / 2, y: (stage.height - size.height) / 2, width: size.width, height: size.height
        )
    }

    /// The smallest side of a rectangle that's a region, in points: less
    /// is a slip of the hand.
    static let minimumSide: CGFloat = 8
    /// How far the pointer moves before a press on the frame is a drag and
    /// not a click, in points.
    static let dragSlop: CGFloat = 4

    /// Whether the pointer, pressed at `start` and now at `current`, drags.
    static func isDrag(from start: CGPoint, to current: CGPoint) -> Bool {
        hypot(current.x - start.x, current.y - start.y) >= dragSlop
    }

    /// Where `region` is on the stage.
    func rect(of region: Region) -> CGRect {
        CGRect(
            x: frame.minX + region.x * frame.width, y: frame.minY + region.y * frame.height,
            width: region.w * frame.width, height: region.h * frame.height
        )
    }

    /// The rectangle a drag from `start` to `current` draws, in any
    /// direction, kept inside the picture.
    func rect(from start: CGPoint, to current: CGPoint) -> CGRect {
        let a = clamp(start), b = clamp(current)
        return CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    /// The region a drag from `start` to `current` draws; nil when the
    /// rectangle is under `minimumSide` either way. Its numbers are kept to
    /// four decimals, finer than a pixel of a 4K frame.
    func region(from start: CGPoint, to current: CGPoint) -> Region? {
        let drawn = rect(from: start, to: current)
        guard drawn.width >= Self.minimumSide, drawn.height >= Self.minimumSide, frame.width > 0, frame.height > 0 else {
            return nil
        }
        let left = Self.round((drawn.minX - frame.minX) / frame.width)
        let top = Self.round((drawn.minY - frame.minY) / frame.height)
        let right = Self.round((drawn.maxX - frame.minX) / frame.width)
        let bottom = Self.round((drawn.maxY - frame.minY) / frame.height)
        return try? Region(x: left, y: top, w: Self.round(right - left), h: Self.round(bottom - top))
    }

    private func clamp(_ point: CGPoint) -> CGPoint {
        CGPoint(x: min(max(point.x, frame.minX), frame.maxX), y: min(max(point.y, frame.minY), frame.maxY))
    }

    private static func round(_ value: CGFloat) -> Double {
        (min(max(Double(value), 0), 1) * 10_000).rounded() / 10_000
    }
}
