import AVKit
import SwiftUI

/// The video's picture: an `AVPlayerView` with no controls of its own. The
/// app draws its own timeline, which carries the markers, and the stage
/// takes the mouse, so this view never takes a click or a key.
struct PlayerSurface: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = PassivePlayerView()
        view.controlsStyle = .none
        view.videoGravity = .resizeAspect
        view.allowsPictureInPicturePlayback = false
        view.allowsMagnification = false
        view.player = player
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        if view.player !== player { view.player = player }
    }

    /// The picture fills the stage it's given. Left to itself the view asks
    /// for the video's own size, and the window grows to it.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: AVPlayerView, context: Context) -> CGSize? {
        proposal.replacingUnspecifiedDimensions()
    }
}

/// An `AVPlayerView` that leaves every event to the views around it.
private final class PassivePlayerView: AVPlayerView {
    override var acceptsFirstResponder: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
