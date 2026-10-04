import SwiftUI

/// The stage: the video on its black letterbox, the layer that takes the
/// mouse and shows regions, the comment box over it while a comment is
/// written, and the notices of what the agent says. A click on the frame plays or pauses; a drag draws a region.
struct StageView: View {
    let model: AppModel

    /// The comment box's size as it was last laid out, for placing it
    /// beside a region.
    @State private var boxSize = CGSize(width: Composer.width, height: 150)

    var body: some View {
        GeometryReader { proxy in
            let geometry = VideoFrameGeometry(stage: proxy.size, video: model.engine.videoSize)
            ZStack(alignment: .topLeading) {
                Theme.letterbox
                PlayerSurface(player: model.engine.player)
                // Above the picture, which takes no events itself.
                RegionOverlay(model: model, geometry: geometry)
                if let draft = model.draft {
                    composer(draft, geometry: geometry, stage: proxy.size)
                        .transition(.opacity)
                }
                // What the agent just said, over everything on the stage.
                Toasts(model: model)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.stageCorner, style: .continuous))
        .padding([.top, .horizontal], Theme.gutter)
        .accessibilityLabel("Video")
    }

    /// The comment box where it belongs: beside the region for a comment
    /// on one, above the playhead at the foot of the stage otherwise.
    @ViewBuilder
    private func composer(_ draft: AppModel.Draft, geometry: VideoFrameGeometry, stage: CGSize) -> some View {
        if let region = draft.region {
            let origin = Composer.placement(beside: geometry.rect(of: region), box: boxSize, stage: stage)
            Composer(model: model, draft: draft, notch: nil)
                .onGeometryChange(for: CGSize.self) { $0.size } action: { boxSize = $0 }
                .offset(x: origin.x, y: origin.y)
        } else {
            let place = Composer.placement(
                fraction: model.engine.duration > 0 ? draft.time / model.engine.duration : 0,
                stageWidth: stage.width
            )
            Composer(model: model, draft: draft, notch: place.notch)
                .padding(.bottom, 4)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .offset(x: place.leading)
        }
    }
}
