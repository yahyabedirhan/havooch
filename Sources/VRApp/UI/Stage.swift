import SwiftUI

/// Where the video shows, with the region layer over it, the comment box
/// while a comment is being written, and the notices of agent messages at
/// its top right. Black in light and dark: video is
/// judged against black, so only the chrome around it follows the appearance.
struct Stage: View {
    let controller: PlayerController
    let model: ReviewModel

    /// The comment box's size as laid out, for placing it beside a region.
    @State private var box = CGSize(width: Composer.regionWidth, height: 180)

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                        text: Binding(get: { model.composerText }, set: { model.composerText = $0 }),
                        commit: { model.commitComposer(text: $0) },
                        cancel: { model.cancelComposer() }
                    )
                    // A new draft is a new box: empty, and focused again.
                    .id(draft)
                    if let region = comment.region {
                        let rect = fit.rect(for: region)
                        let centre = ComposerPlacement.centre(of: box, beside: rect, in: proxy.size)
                        composer
                            .transition(appearing(from: Self.anchor(of: box, at: centre, beside: rect)))
                            .onGeometryChange(for: CGSize.self) { $0.size } action: { box = $0 }
                            .position(centre)
                    } else {
                        composer
                            .transition(appearing(from: .bottom))
                            .padding(Theme.edge)
                    }
                }
            }
            .animation(.spring(duration: 0.25, bounce: 0), value: model.composing)
            .overlay(alignment: .topTrailing) {
                NoticeStack(notices: model.notices) { model.openNotice($0) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// How the comment box comes and goes: a slight grow from the side it
    /// opens from, or only a fade with reduced motion.
    private func appearing(from anchor: UnitPoint) -> AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.97, anchor: anchor))
    }

    /// The side of a box centred at `centre` that faces `rect`: its leading
    /// edge when it stands right of the rectangle, its trailing edge when
    /// left of it, its top when below it, else its bottom.
    private static func anchor(of box: CGSize, at centre: CGPoint, beside rect: CGRect) -> UnitPoint {
        if centre.x - box.width / 2 >= rect.maxX {
            .leading
        } else if centre.x + box.width / 2 <= rect.minX {
            .trailing
        } else if centre.y - box.height / 2 >= rect.maxY {
            .top
        } else {
            .bottom
        }
    }
}
