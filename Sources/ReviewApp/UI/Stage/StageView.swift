import SwiftUI

/// The stage: the video on its black letterbox, the layer that takes the
/// mouse and shows regions, the comment box over it while a comment is
/// written, the threads on the frame, and the notices of what the agent
/// says. A click on the frame plays or pauses; a drag draws a region.
struct StageView: View {
    let model: AppModel

    /// The comment box's size as it was last laid out, for placing it
    /// beside a region.
    @State private var boxSize = CGSize(width: Composer.width, height: 150)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.palette) private var palette

    /// How far the comment box travels as it comes and goes.
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
                    composer(draft, geometry: geometry, stage: proxy.size)
                }
                // What the agent just said, over everything on the stage.
                Toasts(model: model)
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

    /// The comment box where it belongs: beside the region for a comment
    /// on one, above the playhead at the foot of the stage otherwise.
    @ViewBuilder
    private func composer(_ draft: AppModel.Draft, geometry: VideoFrameGeometry, stage: CGSize) -> some View {
        if let region = draft.region {
            let rect = geometry.rect(of: region)
            let origin = Composer.placement(beside: rect, box: boxSize, stage: stage)
            Composer(model: model, draft: draft, notch: nil)
                .onGeometryChange(for: CGSize.self) { $0.size } action: { boxSize = $0 }
                .offset(x: origin.x, y: origin.y)
                .transition(arrival(from: Self.side(of: rect, from: origin, box: boxSize)))
        } else {
            let fraction = model.engine.duration > 0 ? draft.time / model.engine.duration : 0
            let place = Composer.placement(
                playhead: Composer.playhead(fraction: fraction, track: model.trackArea, stage: model.stageArea),
                stageWidth: stage.width
            )
            Composer(model: model, draft: draft, notch: place.notch)
                .padding(.bottom, 4)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .offset(x: place.leading)
                // Up from the playhead its notch points at.
                .transition(arrival(from: CGSize(width: 0, height: Self.arrivalDistance)))
        }
    }

    /// The box comes in from `offset` towards where it sits, and leaves the
    /// same way, so it grows out of what it's about. With reduced motion it
    /// only fades.
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
