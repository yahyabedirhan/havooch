import SwiftUI

/// The stage: the video on its black letterbox. A click on the frame plays
/// or pauses.
struct StageView: View {
    let model: AppModel

    var body: some View {
        ZStack {
            Theme.letterbox
            PlayerSurface(player: model.engine.player)
            // Above the picture, which takes no events itself.
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { model.togglePlay() }
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.stageCorner, style: .continuous))
        .padding([.top, .horizontal], Theme.gutter)
        .accessibilityLabel("Video")
    }
}
