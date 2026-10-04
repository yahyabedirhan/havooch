import SwiftUI

/// The stage: the video on its black letterbox, with the comment box over
/// it while a comment is written. A click on the frame plays or pauses.
struct StageView: View {
    let model: AppModel

    var body: some View {
        ZStack {
            Theme.letterbox
            PlayerSurface(player: model.engine.player)
            // Above the picture, which takes no events itself.
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    // A comment is about the frame on screen: it stays there.
                    if model.draft == nil { model.togglePlay() }
                }
        }
        .overlay(alignment: .bottomLeading) {
            if let draft = model.draft {
                GeometryReader { proxy in
                    let place = Composer.placement(
                        fraction: model.engine.duration > 0 ? draft.time / model.engine.duration : 0,
                        stageWidth: proxy.size.width
                    )
                    Composer(model: model, draft: draft, notch: place.notch)
                        .padding(.bottom, 4)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .offset(x: place.leading)
                }
                .transition(.opacity)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.stageCorner, style: .continuous))
        .padding([.top, .horizontal], Theme.gutter)
        .accessibilityLabel("Video")
    }
}
