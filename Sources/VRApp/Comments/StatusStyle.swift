import SwiftUI
import VRReview

/// One colour, symbol and word per comment state, and one for a comment
/// whose question waits for the person, for the timeline's markers and the
/// sidebar's cards alike, so the two can't disagree.
struct StatusStyle {
    var color: Color
    /// The SF Symbol drawn inside the mark; nil for a plain mark.
    var symbol: String?
    /// A ring, not a filled mark.
    var hollow = false
    /// The symbol moves: the listener is at work on the comment.
    var animated = false
    var label: String

    /// How `comment` shows: by its question while one waits for the
    /// person, since that is what the person can act on, else by its state.
    static func of(_ comment: Comment) -> StatusStyle {
        comment.openQuestion == nil ? of(comment.state) : question
    }

    /// A comment whose question waits for the person.
    static let question = StatusStyle(color: .purple, symbol: "questionmark", label: "Question")

    static func of(_ state: CommentState) -> StatusStyle {
        switch state {
        case .draft: StatusStyle(color: .gray, hollow: true, label: "Draft")
        case .queued: StatusStyle(color: .gray, hollow: true, label: "Queued")
        case .sent: StatusStyle(color: .blue, label: "Sent")
        case .acknowledged: StatusStyle(color: .blue, symbol: "checkmark", label: "Acknowledged")
        case .working: StatusStyle(color: .orange, symbol: "ellipsis", animated: true, label: "Working")
        case .done: StatusStyle(color: .green, symbol: "checkmark", label: "Done")
        case .failed: StatusStyle(color: .red, symbol: "xmark", label: "Failed")
        }
    }
}

/// A comment's standing as a small mark: the marker on the timeline and the
/// dot on its card. It is round for a comment at a time and a rounded
/// square for one on a region, so the two kinds tell apart before a click.
/// The comment in focus gets a ring in the accent colour.
struct StatusMark: View {
    let style: StatusStyle
    /// Whether the comment points at a region of the frame.
    var squared = false
    var selected = false
    var size: CGFloat = 12

    var body: some View {
        let shape = MarkShape(squared: squared)
        ZStack {
            if style.hollow {
                // Filled with the window's colour, so the track doesn't show through the ring.
                shape.fill(.background)
                shape.strokeBorder(style.color, lineWidth: size / 5)
            } else {
                shape.fill(style.color)
                if let symbol = style.symbol {
                    Image(systemName: symbol)
                        .font(.system(size: size * 0.55, weight: .heavy))
                        .foregroundStyle(.white)
                        .symbolEffect(.variableColor.iterative, isActive: style.animated)
                }
            }
        }
        .frame(width: size, height: size)
        .padding(2)
        .overlay {
            if selected { shape.strokeBorder(Color.accentColor, lineWidth: 1.5) }
        }
        .accessibilityLabel(squared ? "\(style.label), on a region" : style.label)
    }
}

/// A mark's outline: a circle, or a square with rounded corners.
private struct MarkShape: InsettableShape {
    var squared: Bool
    var inset: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let rect = rect.insetBy(dx: inset, dy: inset)
        return squared ? Path(roundedRect: rect, cornerRadius: rect.width * 0.28) : Path(ellipseIn: rect)
    }

    func inset(by amount: CGFloat) -> MarkShape {
        MarkShape(squared: squared, inset: inset + amount)
    }
}
