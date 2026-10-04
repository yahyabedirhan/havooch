import SwiftUI

/// Where the video shows, with the comment box over it while a comment is
/// being written. Black in light and dark: video is judged against black,
/// so only the chrome around it follows the appearance.
struct Stage: View {
    let controller: PlayerController
    let model: ReviewModel

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black
            PlayerSurface(player: controller.player)
            if let draft = model.composing, let comment = model.session?.comment(draft) {
                Composer(
                    time: comment.time,
                    commit: { model.commitComposer(text: $0) },
                    cancel: { model.cancelComposer() }
                )
                // A new draft is a new box: empty, and focused again.
                .id(draft)
                .padding(Theme.edge)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
