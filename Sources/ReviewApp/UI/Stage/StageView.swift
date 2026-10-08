import ReviewCore
import ReviewWire
import SwiftUI

/// The stage: the video on its black letterbox, the layer that takes the
/// mouse and shows regions, the popover over it while a message is written
/// or a thread is open, the threads on the frame, and the notices of what
/// the agent says. A click on the frame points and never plays (L67); a
/// drag draws a region. While the window compares two versions (E11),
/// the two pictures in their layout (`CompareStage`).
struct StageView: View {
    let model: WindowModel

    /// The stage in the window, as it was last laid out.
    @State private var area: CGRect = .zero

    var body: some View {
        Group {
            if let pair = model.pair, let session = model.compare, model.isComparing {
                CompareStage(model: model, pair: pair, session: session)
            } else {
                ZStack(alignment: .topLeading) {
                    StagePane(model: model, engine: model.engine)
                    StagePopoverLayer(model: model)
                    // What the agent just said, over everything on the stage.
                    Notices(model: model)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Metrics.stageCorner, style: .continuous))
        // The tour's write step rings the frame (H4); the ring stands in the gutter.
        .coachRing(model.tourRings(.stage), radius: Metrics.stageCorner)
        // Where a click is on the stage, which closes the popover by its own
        // gestures; a click anywhere else is outside it (`OutsideClicks`).
        // Side by side, the active side's pane is the stage (`CompareStage`).
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { area in
            self.area = area
            keepArea()
        }
        .onChange(of: model.compare?.layout) { keepArea() }
        .onChange(of: model.isComparing) { keepArea() }
        .padding([.top, .horizontal], Metrics.gutter)
        .accessibilityLabel("Video")
    }

    /// The whole stage is where a click is on the stage, but side by side.
    private func keepArea() {
        guard !(model.isComparing && model.compare?.layout == .sideBySide) else { return }
        model.stageArea = area
    }
}

/// One picture on the stage: the video of `engine` on its letterbox, the
/// layer that takes the mouse and draws regions, and the threads on its
/// frame. While comparing, one pane per side.
struct StagePane: View {
    let model: WindowModel
    let engine: PlayerEngine
    /// The compare side it shows; nil for the window's one video.
    var side: CompareSide?
    /// How much of its width, from its leading edge, takes the mouse;
    /// nil for all of it. Slider's left side takes it up to the handle.
    var hitWidth: CGFloat?
    @Environment(\.palette) private var palette

    var body: some View {
        GeometryReader { proxy in
            let geometry = VideoFrameGeometry(stage: proxy.size, video: engine.videoSize)
            ZStack(alignment: .topLeading) {
                palette[.letterbox]
                PlayerSurface(player: engine.player)
                // Above the picture, which takes no events itself.
                RegionOverlay(model: model, geometry: geometry, engine: engine, side: side, hitWidth: hitWidth)
                // The threads on this frame: outlines and badges.
                FrameMarks(model: model, geometry: geometry, side: side)
            }
        }
    }
}

/// The popover over the stage while a message is written or a thread is
/// open, on the active picture: where the person left its thread's
/// popover, else beside the region, else above the playhead.
struct StagePopoverLayer: View {
    let model: WindowModel

    /// The popover's size as it was last laid out, for placing it beside a
    /// region, and as the size a first drag or resize starts from.
    @State private var boxSize = CGSize(width: CommentPopover.width, height: 150)
    /// The drag on the popover's header, an edge or a corner under way,
    /// and the thread whose popover it drags: nil for a new message's.
    @State private var drag: (thread: ThreadID?, drag: ThreadPopover.Drag)?
    /// The box the person resized a new message's popover to, on the
    /// stage, and the draft's moment and region it holds for. No thread
    /// keeps it yet (L30), so it goes when the popover closes.
    @State private var sized: (time: Double, region: Region?, box: CGRect)?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// How far the popover travels as it comes and goes.
    private static let arrivalDistance: CGFloat = 8
    /// The space under the notch's tip, at the stage's foot.
    private static let foot: CGFloat = 4

    var body: some View {
        GeometryReader { proxy in
            let geometry = VideoFrameGeometry(stage: proxy.size, video: model.engine.videoSize)
            ZStack(alignment: .topLeading) {
                if let draft = model.draft {
                    commentPopover(draft, geometry: geometry, stage: proxy.size)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            .animation(reduceMotion ? .easeOut(duration: 0.15) : .smooth(duration: 0.2), value: model.draft == nil)
        }
        .onChange(of: model.draft == nil) { _, closed in
            if closed { sized = nil }
        }
    }

    /// Where the popover sits and how it comes in.
    private struct Placement {
        var origin: CGPoint
        /// The size the person gave the box, without its notch; nil for its own size.
        var size: CGSize?
        var notch: CGFloat?
        /// Whether it stands on the foot of the stage, above the playhead.
        var onFoot = false
        var arrival: CGSize = .zero
        /// Where the playhead is across the stage, for a popover on a
        /// moment; nil for one beside a region.
        var playhead: CGFloat?
    }

    /// The popover where it belongs: where the person left its thread's
    /// popover, else beside the region for a message on one, else above
    /// the playhead at the foot of the stage. One view in every place, so
    /// a drag that starts from where it opened keeps going.
    private func commentPopover(_ draft: WindowModel.Draft, geometry: VideoFrameGeometry, stage: CGSize) -> some View {
        let thread = model.draftThread
        let place = placement(draft, thread: thread, geometry: geometry, stage: stage)
        // The box as it shows now, without its notch: where a drag starts.
        let shown = CGRect(
            origin: place.origin,
            size: place.size ?? CGSize(width: boxSize.width, height: boxSize.height - (place.notch == nil ? 0 : CommentPopover.notchHeight))
        )
        return CommentPopover(
            model: model, draft: draft, notch: place.notch, thread: thread, size: place.size,
            move: thread.map { thread in
                { translation, ended in
                    follow(nil, translation, ended: ended, thread: thread.id, draft: draft, from: shown, place: place, stage: stage)
                }
            },
            resize: { handle, translation, ended in
                follow(handle, translation, ended: ended, thread: thread?.id, draft: draft, from: shown, place: place, stage: stage)
            }
        )
        .onGeometryChange(for: CGSize.self) { $0.size } action: { boxSize = $0 }
        .padding(.bottom, place.onFoot ? Self.foot : 0)
        .frame(maxHeight: .infinity, alignment: place.onFoot ? .bottom : .top)
        .offset(x: place.origin.x, y: place.onFoot ? 0 : place.origin.y)
        .transition(arrival(from: place.arrival))
    }

    /// A step of a drag on the popover of `thread`, or of a new message
    /// when it's nil: on the header when `handle` is nil, else on that edge
    /// or corner. The drag's first step keeps `shown`, the box as it was,
    /// and every later step is measured from it, never from the size the
    /// drag gave the box. At its end the thread keeps the popover's frame
    /// in the video area, and a new message's popover keeps its box while
    /// it is open; a drag that came back to where it started keeps nothing.
    private func follow(
        _ handle: FrameResizePosition?, _ translation: CGSize, ended: Bool, thread: ThreadID?, draft: WindowModel.Draft,
        from shown: CGRect, place: Placement, stage: CGSize
    ) {
        var current = drag.flatMap { $0.thread == thread && $0.drag.handle == handle ? $0.drag : nil }
            ?? ThreadPopover.Drag(handle: handle, start: shown)
        current.translation = translation
        guard ended else {
            drag = (thread, current)
            return
        }
        drag = nil
        guard translation != .zero else { return }
        guard let thread else {
            sized = (draft.time, draft.region, Self.newMessageBox(current, playhead: place.playhead, stage: stage))
            return
        }
        do throws(AppRefusal) {
            try model.movePopover(thread, to: ThreadPopover.frame(of: current.rect(in: stage), in: stage))
        } catch {
            model.problem = WindowModel.Problem(title: "The popover's place wasn't kept", reason: error.reason)
        }
    }

    /// A new message's box for the resize `drag` on a stage `stage` in
    /// size, by `CommentPopover.rules` (L70). On a moment, at `playhead`,
    /// the box stays above the notch's room at the stage's foot, and its
    /// sides never pass the notch, which stays on the bottom edge.
    private static func newMessageBox(_ drag: ThreadPopover.Drag, playhead: CGFloat?, stage: CGSize) -> CGRect {
        guard let handle = drag.handle else { return drag.start }
        guard let playhead else {
            let room = CGRect(origin: .zero, size: stage).insetBy(dx: ThreadPopover.margin, dy: ThreadPopover.margin)
            return CommentPopover.rules.resized(drag.start, from: handle, by: drag.translation, in: room)
        }
        let margin: CGFloat = 10
        let room = CGRect(
            x: margin, y: margin, width: stage.width - 2 * margin,
            height: stage.height - margin - foot - CommentPopover.notchHeight
        )
        let notch = (playhead - CommentPopover.notchInset)...(playhead + CommentPopover.notchInset)
        return CommentPopover.rules.resized(drag.start, from: handle, by: drag.translation, in: room, covers: notch)
    }

    private func placement(
        _ draft: WindowModel.Draft, thread: ReviewThread?, geometry: VideoFrameGeometry, stage: CGSize
    ) -> Placement {
        let natural: Placement
        // A thread opened from its pin or badge sits beside its first region.
        if let region = draft.region ?? thread?.messages.lazy.compactMap(\.region).first {
            let rect = geometry.rect(of: region)
            let origin = CommentPopover.placement(beside: rect, box: boxSize, stage: stage)
            natural = Placement(origin: origin, arrival: Self.side(of: rect, from: origin, box: boxSize))
        } else {
            let fraction = model.engine.duration > 0 ? draft.time / model.engine.duration : 0
            let playhead = CommentPopover.playhead(fraction: fraction, track: model.trackArea, stage: model.stageArea)
            let place = CommentPopover.placement(playhead: playhead, stageWidth: stage.width)
            natural = Placement(
                origin: CGPoint(x: place.leading, y: stage.height - Self.foot - boxSize.height), notch: place.notch, onFoot: true,
                // Up from the playhead its notch points at.
                arrival: CGSize(width: 0, height: Self.arrivalDistance), playhead: playhead
            )
        }
        if let drag, drag.thread == thread?.id {
            guard thread != nil else { return Self.sized(Self.newMessageBox(drag.drag, playhead: natural.playhead, stage: stage), natural) }
            return Placement(origin: drag.drag.rect(in: stage).origin, size: drag.drag.rect(in: stage).size)
        }
        if let frame = thread?.popoverFrame {
            let rect = ThreadPopover.rect(of: frame, in: stage)
            return Placement(origin: rect.origin, size: rect.size)
        }
        // A new message's box, kept as it becomes a thread.
        if let sized, sized.time == draft.time, sized.region == draft.region {
            return Self.sized(sized.box, natural)
        }
        return natural
    }

    /// A popover `natural` would place, at the box `box` instead: on a
    /// moment its notch stays on the bottom edge, at the playhead.
    private static func sized(_ box: CGRect, _ natural: Placement) -> Placement {
        let notch = natural.playhead.map {
            min(max($0 - box.minX, CommentPopover.notchInset), max(box.width - CommentPopover.notchInset, CommentPopover.notchInset))
        }
        return Placement(origin: box.origin, size: box.size, notch: notch, arrival: natural.arrival, playhead: natural.playhead)
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
