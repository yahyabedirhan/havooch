import SwiftUI

/// The look's few numbers and fonts, in one place. Colours are the system's,
/// so light and dark both work without a second palette.
enum Theme {
    /// The space between neighbours in a bar or a list.
    static let gap: CGFloat = 12
    /// The space between a bar's content and the window's edge.
    static let edge: CGFloat = 16
    static let transportHeight: CGFloat = 48
    static let bannerHeight: CGFloat = 32
    static let trackHeight: CGFloat = 4
    static let thumbSize: CGFloat = 12
    /// Times, in digits that don't shift as they change.
    static let timeFont = Font.system(.callout, design: .rounded).monospacedDigit()
}
