import AVFoundation
import AppKit
import SwiftUI

/// The video's frame: an `AVPlayerLayer` alone, aspect-fit on black, with
/// none of AVKit's controls, since the app's own timeline carries the
/// markers.
struct PlayerSurface: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> PlayerLayerView {
        PlayerLayerView(player: player)
    }

    func updateNSView(_ view: PlayerLayerView, context: Context) {
        if view.playerLayer.player !== player { view.playerLayer.player = player }
    }
}

/// The view that hosts the player's layer. `Screenshotter` finds it in the
/// window to know where the frame sits.
final class PlayerLayerView: NSView {
    let playerLayer = AVPlayerLayer()

    init(player: AVPlayer) {
        super.init(frame: .zero)
        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspect
        playerLayer.backgroundColor = .black
        // A layer of its own choosing: set before the view asks for one.
        layer = playerLayer
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("PlayerLayerView is made in code")
    }
}
