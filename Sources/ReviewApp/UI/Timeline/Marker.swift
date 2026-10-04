import ReviewCore
import SwiftUI

/// One comment's pin: its number in time order, drawn by its state. A
/// queued comment is hollow; every later state fills the pin with its
/// colour. The same pin heads the comment's card, which ties the two.
struct MarkerPin: View {
    let number: Int
    let state: CommentState
    var isSelected = false

    static let size: CGFloat = 18

    var body: some View {
        Text("\(number)")
            .font(.system(size: number > 99 ? 8 : 10.5, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(isHollow ? AnyShapeStyle(.primary) : AnyShapeStyle(.white))
            .frame(width: Self.size, height: Self.size)
            .background(isHollow ? Color(nsColor: .windowBackgroundColor) : Theme.tint(state), in: Circle())
            .overlay {
                Circle().strokeBorder(
                    isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(isHollow ? .secondary : Theme.tint(state)),
                    lineWidth: isSelected ? 2 : 1.5
                )
            }
            .background {
                if isSelected {
                    Circle().fill(.tint.opacity(0.28)).padding(-4)
                }
            }
    }

    private var isHollow: Bool {
        state == .draft || state == .queued
    }
}

/// The markers above the timeline's track: one pin per comment at its time,
/// with a stem down to the track. A click on a pin selects its comment.
struct MarkerLayer: View {
    let comments: [Comment]
    let duration: Double
    let selection: ItemID?
    let select: (ItemID) -> Void

    /// The stem's length: from the pin down to the track.
    let stem: CGFloat

    var height: CGFloat { MarkerPin.size + stem }

    var body: some View {
        GeometryReader { proxy in
            ForEach(Array(comments.enumerated()), id: \.element.id) { index, comment in
                let isSelected = comment.id == selection
                VStack(spacing: 0) {
                    Button {
                        select(comment.id)
                    } label: {
                        MarkerPin(number: index + 1, state: comment.state, isSelected: isSelected)
                    }
                    .buttonStyle(.plain)
                    .help(comment.text)
                    .accessibilityLabel("Comment \(index + 1), \(Theme.name(comment.state))")
                    Capsule()
                        .fill(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                        .frame(width: 1.5, height: stem)
                        .allowsHitTesting(false)
                }
                .position(x: duration > 0 ? proxy.size.width * min(max(comment.time / duration, 0), 1) : 0, y: height / 2)
                .zIndex(isSelected ? 1 : 0)
            }
        }
        .frame(height: height)
    }
}
