import AppKit
import ReviewCore
import SwiftUI

/// One place for the window's measures and for each comment state's colour,
/// glyph and name, so the stage, the timeline and the rail line up and a
/// state looks the same on a marker and in the rail.
///
/// The colours are muted pastels with a light and a dark variant each, not
/// the system's saturated ones: the video is the loudest thing in the
/// window, and the chrome around it stays quiet. Surfaces are told apart by
/// their background, not by borders.
enum Theme {
    /// The rail's width, and how far a person can resize it.
    static let railWidth: CGFloat = 340
    static let railWidthRange: ClosedRange<CGFloat> = 300...460
    /// The space around the stage and beside the timeline.
    static let gutter: CGFloat = 12
    /// How far the timeline's track is inset from the stage's sides.
    static let laneInset: CGFloat = 4
    static let stageCorner: CGFloat = 12
    /// The height of the timeline lane under the stage and of the rail's
    /// foot, so the stage's lower edge and the line over the rail's foot
    /// are one line across the window.
    static let footerHeight: CGFloat = 116
    /// The side padding of a row in the rail, and of the rail's headers.
    static let railPadding: CGFloat = 16
    /// The letterbox around the video: black in light and dark, as a
    /// player shows it.
    static let letterbox = Color.black

    /// The app's accent: a soft slate blue in place of the system's bright
    /// one, on the scrubber, a selection, a drawn region and the Send button.
    static let accent = pastel(light: 0x5B7DB1, dark: 0x9DB6DD)
    /// The agent's colour, on its messages and its notices.
    static let agent = accent
    /// An open question's colour: on the marker, the thread and the notice.
    /// No state has it, so a question never reads as one.
    static let question = pastel(light: 0x4F918F, dark: 0x8FC7C3)
    /// The agent-control indicator's colour while an agent holds the lease.
    static let control = pastel(light: 0xB98A45, dark: 0xE3BF84)
    /// The words and glyphs drawn on a filled state colour: white on the
    /// deeper light-mode tones, near-black on the lighter dark-mode ones.
    static let onTint = dynamic(light: NSColor.white, dark: NSColor(white: 0.1, alpha: 1))

    /// A message bubble's fill in the rail: the person's and the agent's.
    static let personBubble = Color.primary.opacity(0.06)
    static let agentBubble = agent.opacity(0.12)
    /// The fill of the selected row in the rail.
    static let selectedRow = accent.opacity(0.12)
    /// The fill of a section header band in the rail.
    static let sectionBand = Color.primary.opacity(0.035)

    /// The glyph on a marker's pin for a state the agent set; nil for a
    /// state before the agent has the comment.
    static func pinGlyph(_ state: CommentState) -> String? {
        switch state {
        case .draft, .queued, .sent: nil
        case .acknowledged, .done: "checkmark"
        case .working: "ellipsis"
        case .failed: "xmark"
        }
    }

    /// The state's colour. A state is never told by colour alone: it has a
    /// glyph and a name too.
    static func tint(_ state: CommentState) -> Color {
        switch state {
        case .draft, .queued: .secondary
        case .sent: pastel(light: 0x8A8F98, dark: 0xA7ACB4)
        case .acknowledged: accent
        case .working: pastel(light: 0xB98A45, dark: 0xE3BF84)
        case .done: pastel(light: 0x5E9771, dark: 0x9CCBA8)
        case .failed: pastel(light: 0xB5654F, dark: 0xDE9C84)
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

    /// The state's name as the rail shows it.
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

    /// A colour with a light and a dark variant, each given as `0xRRGGBB`.
    private static func pastel(light: UInt32, dark: UInt32) -> Color {
        dynamic(light: rgb(light), dark: rgb(dark))
    }

    private static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
    }

    private static func rgb(_ hex: UInt32) -> NSColor {
        NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
