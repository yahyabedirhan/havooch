import SwiftUI
import VRReview

/// Where the video's frame is inside the stage: fitted whole, centred, with
/// black bars beside or above it. Everything between the stage's points and
/// a region's normalized frame coordinates goes through it, so a region is
/// on the same part of the picture at any window size.
struct FrameFit: Equatable {
    /// The frame's rectangle in the stage's points; empty with no video or
    /// no room.
    let frame: CGRect

    /// The smallest side a drawn rectangle may have, in points. A smaller
    /// one is a click, not a region.
    static let smallest: CGFloat = 8
    /// A drawn region's parts are kept to this many steps of the frame:
    /// finer than a pixel of any video, and short to read.
    private static let steps = 10_000.0

    init(video: CGSize, stage: CGSize) {
        guard video.width > 0, video.height > 0, stage.width > 0, stage.height > 0 else {
            frame = .zero
            return
        }
        let scale = min(stage.width / video.width, stage.height / video.height)
        let size = CGSize(width: video.width * scale, height: video.height * scale)
        frame = CGRect(
            x: (stage.width - size.width) / 2,
            y: (stage.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
    }

    /// Where `region` is in the stage.
    func rect(for region: Region) -> CGRect {
        CGRect(
            x: frame.minX + region.x * frame.width,
            y: frame.minY + region.y * frame.height,
            width: region.w * frame.width,
            height: region.h * frame.height
        )
    }

    /// The rectangle a drag from `start` to `end` draws, in the stage: any
    /// direction, with a point outside the frame kept on its edge.
    func selection(from start: CGPoint, to end: CGPoint) -> CGRect {
        let a = clamped(start)
        let b = clamped(end)
        return CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    /// The region a drag from `start` to `end` draws, or nil when it's too
    /// small to be one.
    func region(from start: CGPoint, to end: CGPoint) -> Region? {
        let drawn = selection(from: start, to: end)
        guard frame.width > 0, frame.height > 0, drawn.width >= Self.smallest, drawn.height >= Self.smallest else {
            return nil
        }
        let left = Self.kept((drawn.minX - frame.minX) / frame.width)
        let top = Self.kept((drawn.minY - frame.minY) / frame.height)
        let right = Self.kept((drawn.maxX - frame.minX) / frame.width)
        let bottom = Self.kept((drawn.maxY - frame.minY) / frame.height)
        return try? Region(x: left, y: top, w: Self.kept(right - left), h: Self.kept(bottom - top))
    }

    private func clamped(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(point.x, frame.minX), frame.maxX),
            y: min(max(point.y, frame.minY), frame.maxY)
        )
    }

    private static func kept(_ part: Double) -> Double {
        min(max((part * steps).rounded() / steps, 0), 1)
    }
}

/// One rectangle the stage draws over the frame.
struct RegionMark: Equatable, Identifiable {
    var id: String
    var region: Region
    /// The region of the comment being written: the frame around it is
    /// dimmed, as while it's drawn.
    var isDraft: Bool

    /// How near the player's time a comment's time must be for its region to
    /// show while its card isn't selected, in seconds.
    static let near = 0.5

    /// The regions to draw: the one of the comment the box is open on, the
    /// selected comment's, and those of the comments at the player's time.
    /// The frame stays clean otherwise.
    static func shown(of comments: [Comment], selection: String?, composing: String?, time: Double) -> [RegionMark] {
        comments.compactMap { comment in
            guard let region = comment.region else { return nil }
            if comment.state == .draft {
                return comment.id == composing ? RegionMark(id: comment.id, region: region, isDraft: true) : nil
            }
            guard comment.id == selection || abs(comment.time - time) <= near else { return nil }
            return RegionMark(id: comment.id, region: region, isDraft: false)
        }
    }
}

/// Where the comment box goes for a comment on a region: beside the
/// rectangle, so writing happens where the person points and the box never
/// covers what it's about.
enum ComposerPlacement {
    /// The space between the box and the rectangle, and the stage's edge.
    static let gap: CGFloat = 12

    /// The centre of a box of `box` beside `rect` in a stage of `stage`:
    /// right of it, else left of it, else below it; when none has room, at
    /// the stage's bottom centre, where a comment without a region has it.
    static func centre(of box: CGSize, beside rect: CGRect, in stage: CGSize) -> CGPoint {
        // Kept inside the stage along the side the box runs on.
        let top = min(max(rect.minY, gap), max(gap, stage.height - gap - box.height))
        let left = min(max(rect.midX - box.width / 2, gap), max(gap, stage.width - gap - box.width))
        let origin: CGPoint
        if rect.maxX + gap + box.width + gap <= stage.width {
            origin = CGPoint(x: rect.maxX + gap, y: top)
        } else if rect.minX - gap - box.width - gap >= 0 {
            origin = CGPoint(x: rect.minX - gap - box.width, y: top)
        } else if rect.maxY + gap + box.height + gap <= stage.height {
            origin = CGPoint(x: left, y: rect.maxY + gap)
        } else {
            origin = CGPoint(x: (stage.width - box.width) / 2, y: stage.height - gap - box.height)
        }
        return CGPoint(x: origin.x + box.width / 2, y: origin.y + box.height / 2)
    }
}

/// The layer over the video where a rectangle is drawn and regions show. A
/// drag draws one, like Cmd+Shift+4: the video pauses, the frame around the
/// rectangle dims, and letting go opens the comment box on it. Regions are
/// drawn from their normalized values on every layout.
struct RegionOverlay: View {
    let fit: FrameFit
    let model: ReviewModel

    /// The drag in progress, in the stage's points.
    @State private var stroke: Stroke?

    private struct Stroke: Equatable {
        var start: CGPoint
        var end: CGPoint
    }

    var body: some View {
        let marks = model.marks
        let drawn = stroke.map { fit.selection(from: $0.start, to: $0.end) }
        ZStack {
            if let lit = drawn ?? marks.first(where: \.isDraft).map({ fit.rect(for: $0.region) }) {
                Path { path in
                    path.addRect(fit.frame)
                    path.addRect(lit)
                }
                .fill(.black.opacity(0.45), style: FillStyle(eoFill: true))
            }
            ForEach(marks) { mark in
                outline(fit.rect(for: mark.region), colour: mark.isDraft ? .white : .accentColor)
            }
            if let drawn {
                outline(drawn, colour: .white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 4)
                .onChanged { drag in
                    if stroke != nil {
                        stroke?.end = drag.location
                    } else if model.beginDrawing() {
                        stroke = Stroke(start: drag.startLocation, end: drag.location)
                    }
                }
                .onEnded { drag in
                    guard let drawn = stroke else { return }
                    stroke = nil
                    if let region = fit.region(from: drawn.start, to: drag.location) {
                        model.compose(region: region)
                    }
                }
        )
    }

    /// A rectangle's edge, readable on a light and on a dark frame.
    private func outline(_ rect: CGRect, colour: Color) -> some View {
        ZStack {
            Path(rect).stroke(.black.opacity(0.55), lineWidth: 4)
            Path(rect).stroke(colour, lineWidth: 2)
        }
    }
}
