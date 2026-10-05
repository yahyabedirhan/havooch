import SwiftUI
import VRReview

/// The look's few numbers and fonts, in one place. Colours are the system's,
/// so light and dark both work without a second palette.
enum Theme {
    /// The space between neighbours in a bar or a list.
    static let gap: CGFloat = 12
    /// The space between a bar's content and the window's edge.
    static let edge: CGFloat = 16
    /// The height of the bars along the window's bottom: the transport bar
    /// under the stage and the send bar under the comments, so the two line
    /// up as one band.
    static let footerHeight: CGFloat = 52
    static let trackHeight: CGFloat = 4
    static let thumbSize: CGFloat = 12
    /// A comment's pin above the track, and the pin of the selected one.
    static let pinSize: CGFloat = 11
    static let selectedPinSize: CGFloat = 13
    static let sidebarWidth: CGFloat = 340
    static let cardCorner: CGFloat = 8
    /// Times, in digits that don't shift as they change.
    static let timeFont = Font.system(.callout, design: .rounded).monospacedDigit()
    /// A comment's time at the head of its card: the transport's digits, not
    /// rounded, a little heavier than the text under it.
    static let cardTimeFont = Font.callout.monospacedDigit().weight(.medium)

    /// A hue made soft: mixed toward grey, so a state shows without being
    /// the loudest thing on screen.
    static func soft(_ colour: Color) -> Color {
        colour.mix(with: .gray, by: 0.35)
    }

    /// A comment state's colour. Never the only sign: `glyph` says the same.
    /// Only a failure stays fully red.
    static func colour(for state: CommentState) -> Color {
        switch state {
        case .draft, .queued: .gray
        case .sent, .acknowledged: soft(.blue)
        case .working: soft(.orange)
        case .done: soft(.green)
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

    /// The colour of an open question: the agent waits for the person.
    static let question = soft(.orange)

    /// The tint of the toolbar's sign that an agent controls the app: a
    /// soft orange, so it shows without shouting.
    static let agent = soft(.orange)

    /// Who wrote a thread message and what it is, as a word in a card.
    static func label(for message: ThreadMessage) -> String {
        switch (message.author, message.kind) {
        case (.agent, .question): "Agent asks"
        case (.agent, _): "Agent"
        case (.person, .answer): "You answered"
        case (.person, _): "You"
        }
    }

    static func glyph(for message: ThreadMessage) -> String {
        switch message.kind {
        case .message: "bubble.left.fill"
        case .question: "questionmark.bubble.fill"
        case .answer: "arrowshape.turn.up.left.fill"
        }
    }

    static func colour(for message: ThreadMessage) -> Color {
        switch message.kind {
        case .message: soft(.accentColor)
        case .question: question
        case .answer: .secondary
        }
    }

    /// The listener's presence as the send bar's chip says it.
    static func label(for presence: Outbox.Presence) -> String {
        switch presence {
        case .absent: "No listener"
        case .listening: "Listening"
        case .working: "Working"
        }
    }

    static func glyph(for presence: Outbox.Presence) -> String {
        switch presence {
        case .absent: "antenna.radiowaves.left.and.right.slash"
        case .listening: "antenna.radiowaves.left.and.right"
        case .working: "ellipsis.circle.fill"
        }
    }

    static func colour(for presence: Outbox.Presence) -> Color {
        switch presence {
        case .absent: .secondary
        case .listening: soft(.green)
        case .working: soft(.orange)
        }
    }
}
