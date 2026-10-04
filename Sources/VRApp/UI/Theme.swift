import SwiftUI
import VRReview

/// The look's few numbers and fonts, in one place. Colours are the system's,
/// so light and dark both work without a second palette.
enum Theme {
    /// The space between neighbours in a bar or a list.
    static let gap: CGFloat = 12
    /// The space between a bar's content and the window's edge.
    static let edge: CGFloat = 16
    static let transportHeight: CGFloat = 52
    static let bannerHeight: CGFloat = 32
    static let trackHeight: CGFloat = 4
    static let thumbSize: CGFloat = 12
    /// A comment's pin above the track, and the pin of the selected one.
    static let pinSize: CGFloat = 9
    static let selectedPinSize: CGFloat = 13
    static let sidebarWidth: CGFloat = 340
    static let cardCorner: CGFloat = 8
    /// Times, in digits that don't shift as they change.
    static let timeFont = Font.system(.callout, design: .rounded).monospacedDigit()

    /// A comment state's colour. Never the only sign: `glyph` says the same.
    static func colour(for state: CommentState) -> Color {
        switch state {
        case .draft, .queued: .gray
        case .sent, .acknowledged: .blue
        case .working: .orange
        case .done: .green
        case .failed: .red
        }
    }

    /// A comment state's SF Symbol.
    static func glyph(for state: CommentState) -> String {
        switch state {
        case .draft: "pencil.circle"
        case .queued: "circle"
        case .sent: "arrow.up.circle.fill"
        case .acknowledged: "checkmark.circle"
        case .working: "ellipsis.circle.fill"
        case .done: "checkmark.circle.fill"
        case .failed: "xmark.circle.fill"
        }
    }

    /// A comment state as a word in a card.
    static func label(for state: CommentState) -> String {
        state.rawValue.prefix(1).uppercased() + state.rawValue.dropFirst()
    }
}
