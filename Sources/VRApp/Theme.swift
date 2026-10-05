import AppKit
import SwiftUI

/// The look's few colours and sizes, in one place, so the frame's side and
/// the sidebar can't drift apart.
///
/// The colours are soft, pastel tones, one per meaning, each with a light
/// and a dark variant. Never the only sign: a symbol or a word says the same.
enum Theme {
    /// A comment that is done; a listener that listens.
    static let sage = adaptive(light: (0.42, 0.66, 0.52), dark: (0.55, 0.78, 0.63))
    /// A comment on its way to the listener, or acknowledged by it.
    static let sky = adaptive(light: (0.44, 0.60, 0.80), dark: (0.56, 0.70, 0.90))
    /// Work in progress: a comment being worked on, a listener at work, a
    /// batch that waits for a listener, an agent that controls the app.
    static let apricot = adaptive(light: (0.86, 0.60, 0.38), dark: (0.93, 0.70, 0.50))
    /// A comment that failed.
    static let coral = adaptive(light: (0.82, 0.45, 0.42), dark: (0.90, 0.56, 0.53))
    /// A question from the agent that waits for the person.
    static let honey = adaptive(light: (0.80, 0.65, 0.28), dark: (0.90, 0.77, 0.42))

    /// The height of the bars at the foot of the window: the transport bar
    /// under the frame and the send bar under the sidebar, so their tops
    /// line up across the window.
    static let footerHeight: CGFloat = 52
    /// The sidebar's width.
    static let sidebarWidth: CGFloat = 320
    /// The space between a bar's content and the window's edge.
    static let edge: CGFloat = 16
    /// The corner of a message bubble, a thumbnail's is smaller.
    static let bubbleCorner: CGFloat = 10

    /// A colour that follows the window's appearance.
    private static func adaptive(light: (Double, Double, Double), dark: (Double, Double, Double)) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let rgb = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
        })
    }
}
