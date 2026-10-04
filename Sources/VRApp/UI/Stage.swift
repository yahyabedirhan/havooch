import SwiftUI

/// Where the video shows, with the region layer over it and the comment box
/// while a comment is being written. Black in light and dark: video is
/// judged against black, so only the chrome around it follows the appearance.
struct Stage: View {
    let controller: PlayerController
    let model: ReviewModel

    /// The comment box's size as laid out, for placing it beside a region.
    @State private var box = CGSize(width: Composer.regionWidth, height: 180)

    var body: some View {
        GeometryReader { proxy in
            let fit = FrameFit(video: model.video?.size ?? .zero, stage: proxy.size)
            ZStack(alignment: .bottom) {
                Color.black
                PlayerSurface(player: controller.player)
                RegionOverlay(fit: fit, model: model)
                if let draft = model.composing, let comment = model.session?.comment(draft) {
                    let composer = Composer(
                        time: comment.time,
                        isOnRegion: comment.region != nil,
                        commit: { model.commitComposer(text: $0) },
                        cancel: { model.cancelComposer() }
                    )
                    // A new draft is a new box: empty, and focused again.
                    .id(draft)
                    if let region = comment.region {
                        composer
                            .onGeometryChange(for: CGSize.self) { $0.size } action: { box = $0 }
                            .position(ComposerPlacement.centre(of: box, beside: fit.rect(for: region), in: proxy.size))
                    } else {
                        composer.padding(Theme.edge)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
