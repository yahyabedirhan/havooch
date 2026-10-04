import ReviewCore
import SwiftUI

/// One place for the window's measures and for each comment state's colour,
/// glyph and name, so the stage, the timeline and the rail line up and a
/// state looks the same on a marker and on a card.
enum Theme {
    /// The rail's width, and how far a person can resize it.
    static let railWidth: CGFloat = 340
    static let railWidthRange: ClosedRange<CGFloat> = 300...460
    /// The space around the stage and beside the timeline.
    static let gutter: CGFloat = 12
    /// How far the timeline's track is inset from the stage's sides.
    static let laneInset: CGFloat = 4
    static let stageCorner: CGFloat = 12
    /// The letterbox around the video: black in light and dark, as a
    /// player shows it.
    static let letterbox = Color.black

    /// The state's colour. A state is never told by colour alone: it has a
    /// glyph and a name too.
    static func tint(_ state: CommentState) -> Color {
        switch state {
        case .draft, .queued: .secondary
        case .sent: .gray
        case .acknowledged: .blue
        case .working: .orange
        case .done: .green
        case .failed: .red
        }
    }

    /// The state's glyph, an SF Symbol.
    static func glyph(_ state: CommentState) -> String {
        switch state {
        case .draft: "pencil.circle"
        case .queued: "circle.dashed"
        case .sent: "arrow.up.circle.fill"
        case .acknowledged: "checkmark.circle"
        case .working: "ellipsis.circle.fill"
        case .done: "checkmark.circle.fill"
        case .failed: "xmark.circle.fill"
        }
    }

    /// The state's name as a card shows it.
    static func name(_ state: CommentState) -> String {
        switch state {
        case .draft: "Draft"
        case .queued: "Queued"
        case .sent: "Sent"
        case .acknowledged: "Acknowledged"
        case .working: "Working"
        case .done: "Done"
        case .failed: "Failed"
        }
    }
}
