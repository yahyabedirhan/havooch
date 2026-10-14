import ReviewCore
import ReviewWire
import SwiftUI

struct StageView: View {
    let model: WindowModel

    @State private var area: CGRect = .zero

    var body: some View {
        Group {
            if let pair = model.pair, let session = model.compare, model.isComparing {
                CompareStage(model: model, pair: pair, session: session)
            } else {
                ZStack(alignment: .topLeading) {
                    StagePane(model: model, engine: model.engine)
                    StagePopoverLayer(model: model)
                    Notices(model: model)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Metrics.stageCorner, style: .continuous))
        .coachRing(model.tourRings(.stage), radius: Metrics.stageCorner)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { area in
            self.area = area
            keepArea()
        }
        .onChange(of: model.compare?.layout) { keepArea() }
        .onChange(of: model.isComparing) { keepArea() }
        .padding([.top, .horizontal], Metrics.gutter)
        .accessibilityLabel("Video")
    }

    private func keepArea() {
        guard !(model.isComparing && model.compare?.layout == .sideBySide) else { return }
        model.stageArea = area
    }
}

struct StagePane: View {
    let model: WindowModel
    let engine: PlayerEngine
    var side: CompareSide?
    var hitWidth: CGFloat?
    @Environment(\.palette) private var palette

    var body: some View {
        GeometryReader { proxy in
            let geometry = VideoFrameGeometry(stage: proxy.size, video: engine.videoSize)
            ZStack(alignment: .topLeading) {
                palette[.letterbox]
                PlayerSurface(player: engine.player)
                RegionOverlay(model: model, geometry: geometry, engine: engine, side: side, hitWidth: hitWidth)
                FrameMarks(model: model, geometry: geometry, side: side)
            }
        }
    }
}

struct StagePopoverLayer: View {
    let model: WindowModel

    @State private var boxSize = CGSize(width: CommentPopover.width, height: 150)
    @State private var drag: (thread: ThreadID?, drag: ThreadPopover.Drag)?
    @State private var sized: (time: Double, region: Region?, box: CGRect)?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let arrivalDistance: CGFloat = 8
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

    private struct Placement {
        var origin: CGPoint
        var size: CGSize?
        var notch: CGFloat?
        var onFoot = false
        var arrival: CGSize = .zero
        var playhead: CGFloat?
    }

    private func commentPopover(_ draft: WindowModel.Draft, geometry: VideoFrameGeometry, stage: CGSize) -> some View {
        let thread = model.draftThread
        let place = placement(draft, thread: thread, geometry: geometry, stage: stage)
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
        if let sized, sized.time == draft.time, sized.region == draft.region {
            return Self.sized(sized.box, natural)
        }
        return natural
    }

    private static func sized(_ box: CGRect, _ natural: Placement) -> Placement {
        let notch = natural.playhead.map {
            min(max($0 - box.minX, CommentPopover.notchInset), max(box.width - CommentPopover.notchInset, CommentPopover.notchInset))
        }
        return Placement(origin: box.origin, size: box.size, notch: notch, arrival: natural.arrival, playhead: natural.playhead)
    }

    private func arrival(from offset: CGSize) -> AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .offset(offset))
    }

    private static func side(of rect: CGRect, from origin: CGPoint, box: CGSize) -> CGSize {
        if origin.x >= rect.maxX { return CGSize(width: -arrivalDistance, height: 0) }
        if origin.x + box.width <= rect.minX { return CGSize(width: arrivalDistance, height: 0) }
        if origin.y >= rect.maxY { return CGSize(width: 0, height: -arrivalDistance) }
        if origin.y + box.height <= rect.minY { return CGSize(width: 0, height: arrivalDistance) }
        return .zero
    }
}
