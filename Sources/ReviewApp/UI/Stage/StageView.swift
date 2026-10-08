import ReviewCore
import SwiftUI

/// The stage: the video on its black letterbox, the layer that takes the
/// mouse and shows regions, the popover over it while a message is written
/// or a thread is open, the threads on the frame, and the notices of what
/// the agent says. A click on the frame plays or pauses; a drag draws a
/// region.
struct StageView: View {
    let model: WindowModel

    /// The popover's size as it was last laid out, for placing it beside a
    /// region, and as the size a first drag or resize starts from.
    @State private var boxSize = CGSize(width: CommentPopover.width, height: 150)
    /// The drag on the popover's header under way: how far it has gone.
    @State private var moving: CGSize = .zero
    /// The drag on the popover's corner grip under way.
    @State private var growing: CGSize = .zero
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.palette) private var palette

    /// How far the popover travels as it comes and goes.
    private static let arrivalDistance: CGFloat = 8

    var body: some View {
        GeometryReader { proxy in
            let geometry = VideoFrameGeometry(stage: proxy.size, video: model.engine.videoSize)
            ZStack(alignment: .topLeading) {
                palette[.letterbox]
                PlayerSurface(player: model.engine.player)
                // Above the picture, which takes no events itself.
                RegionOverlay(model: model, geometry: geometry)
                // The threads on this frame: outlines and badges.
                FrameMarks(model: model, geometry: geometry)
                if let draft = model.draft {
                    commentPopover(draft, geometry: geometry, stage: proxy.size)
                }
                // What the agent just said, over everything on the stage.
                Notices(model: model)
            }
            .animation(reduceMotion ? .easeOut(duration: 0.15) : .smooth(duration: 0.2), value: model.draft == nil)
        }
        .clipShape(RoundedRectangle(cornerRadius: Metrics.stageCorner, style: .continuous))
        // Where a click is on the stage, which closes the popover by its own
        // gestures; a click anywhere else is outside it (`OutsideClicks`).
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { model.stageArea = $0 }
        .padding([.top, .horizontal], Metrics.gutter)
        .accessibilityLabel("Video")
    }

    /// Where the popover sits and how it comes in.
    private struct Placement {
        var origin: CGPoint
        /// The size the person gave it; nil for its own size.
        var size: CGSize?
        var notch: CGFloat?
        /// Whether it stands on the foot of the stage, above the playhead.
        var onFoot = false
        var arrival: CGSize = .zero
    }

    /// The popover where it belongs: where the person left its thread's
    /// popover, else beside the region for a message on one, else above
    /// the playhead at the foot of the stage. One view in every place, so
    /// a drag that starts from where it opened keeps going.
    private func commentPopover(_ draft: WindowModel.Draft, geometry: VideoFrameGeometry, stage: CGSize) -> some View {
        let thread = model.draftThread
        let place = placement(draft, thread: thread, geometry: geometry, stage: stage, moving: moving, growing: growing)
        return CommentPopover(
            model: model, draft: draft, notch: place.notch, thread: thread, size: place.size,
            move: thread.map { thread in
                { translation, ended in
                    moving = translation
                    guard ended else { return }
                    keep(thread, draft: draft, geometry: geometry, stage: stage, moving: translation, growing: .zero)
                }
            },
            resize: thread.map { thread in
                { translation, ended in
                    growing = translation
                    guard ended else { return }
                    keep(thread, draft: draft, geometry: geometry, stage: stage, moving: .zero, growing: translation)
                }
            }
        )
        .onGeometryChange(for: CGSize.self) { $0.size } action: { boxSize = $0 }
        .padding(.bottom, place.onFoot ? 4 : 0)
        .frame(maxHeight: .infinity, alignment: place.onFoot ? .bottom : .top)
        .offset(x: place.origin.x, y: place.onFoot ? 0 : place.origin.y)
        .transition(arrival(from: place.arrival))
    }

    /// The end of a drag or a resize: the thread keeps the popover's frame
    /// in the video area, and the gesture's offsets are spent.
    private func keep(
        _ thread: ReviewThread, draft: WindowModel.Draft, geometry: VideoFrameGeometry, stage: CGSize,
        moving: CGSize, growing: CGSize
    ) {
        let place = placement(draft, thread: thread, geometry: geometry, stage: stage, moving: moving, growing: growing)
        let rect = CGRect(origin: place.origin, size: place.size ?? boxSize)
        do throws(AppRefusal) {
            try model.movePopover(thread.id, to: ThreadPopover.frame(of: rect, in: stage))
        } catch {
            model.problem = WindowModel.Problem(title: "The popover's place wasn't kept", reason: error.reason)
        }
        self.moving = .zero
        self.growing = .zero
    }

    private func placement(
        _ draft: WindowModel.Draft, thread: ReviewThread?, geometry: VideoFrameGeometry, stage: CGSize,
        moving: CGSize, growing: CGSize
    ) -> Placement {
        let natural: Placement
        // A thread opened from its pin or badge sits beside its first region.
        if let region = draft.region ?? thread?.messages.lazy.compactMap(\.region).first {
            let rect = geometry.rect(of: region)
            let origin = CommentPopover.placement(beside: rect, box: boxSize, stage: stage)
            natural = Placement(origin: origin, arrival: Self.side(of: rect, from: origin, box: boxSize))
        } else {
            let fraction = model.engine.duration > 0 ? draft.time / model.engine.duration : 0
            let place = CommentPopover.placement(
                playhead: CommentPopover.playhead(fraction: fraction, track: model.trackArea, stage: model.stageArea),
                stageWidth: stage.width
            )
            natural = Placement(
                origin: CGPoint(x: place.leading, y: stage.height - 4 - boxSize.height), notch: place.notch, onFoot: true,
                // Up from the playhead its notch points at.
                arrival: CGSize(width: 0, height: Self.arrivalDistance)
            )
        }
        guard let thread, thread.popoverFrame != nil || moving != .zero || growing != .zero else { return natural }
        let base = thread.popoverFrame.map { ThreadPopover.rect(of: $0, in: stage) } ?? CGRect(origin: natural.origin, size: boxSize)
        let rect = ThreadPopover.fit(
            CGRect(
                x: base.minX + moving.width, y: base.minY + moving.height,
                width: base.width + growing.width, height: base.height + growing.height
            ),
            in: stage
        )
        return Placement(origin: rect.origin, size: rect.size)
    }

    /// The popover comes in from `offset` towards where it sits, and leaves
    /// the same way, so it grows out of what it's about. With reduced motion
    /// it only fades.
    private func arrival(from offset: CGSize) -> AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .offset(offset))
    }

    /// The direction from the box at `origin` back towards the rectangle
    /// `rect` it's beside, `arrivalDistance` long.
    private static func side(of rect: CGRect, from origin: CGPoint, box: CGSize) -> CGSize {
        if origin.x >= rect.maxX { return CGSize(width: -arrivalDistance, height: 0) }
        if origin.x + box.width <= rect.minX { return CGSize(width: arrivalDistance, height: 0) }
        if origin.y >= rect.maxY { return CGSize(width: 0, height: -arrivalDistance) }
        if origin.y + box.height <= rect.minY { return CGSize(width: 0, height: arrivalDistance) }
        return .zero
    }
}
