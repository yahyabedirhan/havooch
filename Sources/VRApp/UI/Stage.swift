import SwiftUI

/// Where the video shows. Black in light and dark: video is judged against
/// black, so only the chrome around it follows the appearance.
struct Stage: View {
    let controller: PlayerController

    var body: some View {
        ZStack {
            Color.black
            PlayerSurface(player: controller.player)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
