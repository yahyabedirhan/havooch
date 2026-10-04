import SwiftUI

/// One place for the window's measures, so the stage, the timeline and the
/// rail line up.
enum Theme {
    /// The rail's width, and how far a person can resize it.
    static let railWidth: CGFloat = 340
    static let railWidthRange: ClosedRange<CGFloat> = 300...460
    /// The space around the stage and beside the timeline.
    static let gutter: CGFloat = 12
    static let stageCorner: CGFloat = 12
    /// The letterbox around the video: black in light and dark, as a
    /// player shows it.
    static let letterbox = Color.black
}
