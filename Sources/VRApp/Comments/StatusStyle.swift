import SwiftUI
import VRReview

/// One colour, symbol and word per comment state, for the timeline's
/// markers and the sidebar's cards alike, so the two can't disagree.
struct StatusStyle {
    var color: Color
    /// The SF Symbol drawn inside the mark; nil for a plain mark.
    var symbol: String?
    /// A ring, not a filled mark.
    var hollow = false
    var label: String

    static func of(_ state: CommentState) -> StatusStyle {
        switch state {
        case .draft: StatusStyle(color: .gray, hollow: true, label: "Draft")
        case .queued: StatusStyle(color: .gray, hollow: true, label: "Queued")
        case .sent: StatusStyle(color: .blue, label: "Sent")
        case .acknowledged: StatusStyle(color: .blue, symbol: "checkmark", label: "Acknowledged")
        case .working: StatusStyle(color: .orange, label: "Working")
        case .done: StatusStyle(color: .green, symbol: "checkmark", label: "Done")
        case .failed: StatusStyle(color: .red, symbol: "xmark", label: "Failed")
        }
    }
}

/// A comment's state as a round mark: the marker on the timeline and the
/// dot on its card. The comment in focus gets a ring in the accent colour.
struct StatusMark: View {
    let state: CommentState
    var selected = false
    var size: CGFloat = 12

    var body: some View {
        let style = StatusStyle.of(state)
        ZStack {
            if style.hollow {
                // Filled with the window's colour, so the track doesn't show through the ring.
                Circle().fill(.background)
                Circle().strokeBorder(style.color, lineWidth: size / 5)
            } else {
                Circle().fill(style.color)
                if let symbol = style.symbol {
                    Image(systemName: symbol)
                        .font(.system(size: size * 0.55, weight: .heavy))
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(width: size, height: size)
        .padding(2)
        .overlay {
            if selected { Circle().strokeBorder(Color.accentColor, lineWidth: 1.5) }
        }
        .accessibilityLabel(style.label)
    }
}
