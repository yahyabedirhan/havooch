import ReviewCore
import SwiftUI

/// One place for the window's measures, so the stage, the timeline and the
/// rail line up. Colours are the theme's (`Palette`), never here.
enum Metrics {
    /// The rail's width, and how far a person can resize it.
    static let railWidth: CGFloat = 340
    static let railWidthRange: ClosedRange<CGFloat> = 300...460
    /// The space around the stage and beside the timeline.
    static let gutter: CGFloat = 12
    /// How far the composer's pointer is inset from the stage's sides.
    static let laneInset: CGFloat = 4
    static let stageCorner: CGFloat = 12
    /// The height of the player bar under the stage and of the sidebar's
    /// footer, so the two meet on one line across the window (D 4.9).
    static let barHeight: CGFloat = 52
    /// The space between a bar's content and the window's edge.
    static let barPadding: CGFloat = 16
    /// The side padding of a row in the rail, and of the rail's headers.
    static let railPadding: CGFloat = 16
}

/// How a message state shows besides its colour: a glyph and a name, so a
/// state is never told by colour alone. Its colour is `Palette.state`.
enum StateLook {
    /// The glyph on a pin for a state the agent set; nil for a
    /// state before the agent has the message.
    static func pinGlyph(_ state: MessageState) -> String? {
        switch state {
        case .queued, .sent: nil
        case .acknowledged, .done: "checkmark"
        case .working: "ellipsis"
        case .failed: "xmark"
        }
    }

    /// The state's glyph, an SF Symbol.
    static func glyph(_ state: MessageState) -> String {
        switch state {
        case .queued: "circle.dashed"
        case .sent: "arrow.up.circle.fill"
        case .acknowledged: "checkmark.circle"
        case .working: "ellipsis.circle.fill"
        case .done: "checkmark.circle.fill"
        case .failed: "xmark.circle.fill"
        }
    }

    /// The state's name as the rail shows it.
    static func name(_ state: MessageState) -> String {
        switch state {
        case .queued: "Queued"
        case .sent: "Sent"
        case .acknowledged: "Acknowledged"
        case .working: "Working"
        case .done: "Done"
        case .failed: "Failed"
        }
    }
}
