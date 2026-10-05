import ReviewCore
import SwiftUI

/// One comment's pin: its number in time order, drawn by its state. A
/// queued comment is hollow; every later state fills the pin with its
/// colour, and a state the agent set adds its glyph at the pin's foot. A
/// badge at its head says the agent waits for an answer, or said something
/// the person hasn't looked at. The same pin heads the comment's row in
/// the rail, which ties the two.
struct MarkerPin: View {
    /// What the agent left on a comment for the person.
    enum Badge: Equatable {
        /// A message the person hasn't looked at.
        case unread
        /// A question that waits for an answer.
        case question

        /// The badge of `comment`: an open question comes before an
        /// unread message, since the agent waits for it.
        init?(_ comment: Comment, unread: Set<ItemID>) {
            if comment.openQuestion != nil {
                self = .question
            } else if unread.contains(comment.id) {
                self = .unread
            } else {
                return nil
            }
        }
    }

    let number: Int
    let state: CommentState
    var isSelected = false
    var badge: Badge?

    static let size: CGFloat = 18
    /// How far a badge or a state glyph stands out from the pin.
    static let overhang: CGFloat = 4

    var body: some View {
        Text("\(number)")
            .font(.system(size: number > 99 ? 8 : 10.5, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(isHollow ? AnyShapeStyle(.primary) : AnyShapeStyle(Theme.onTint))
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
            .overlay(alignment: .bottomTrailing) {
                if let glyph = Theme.pinGlyph(state) {
                    stateGlyph(glyph).offset(x: Self.overhang, y: Self.overhang)
                }
            }
            .overlay(alignment: .topTrailing) {
                if let badge {
                    badgeView(badge).offset(x: Self.overhang, y: -Self.overhang)
                }
            }
    }

    /// The state's glyph in a small disc on the window's colour, so it
    /// reads on the pin and beside it: a state is told by shape too.
    private func stateGlyph(_ glyph: String) -> some View {
        Image(systemName: glyph)
            .font(.system(size: 7, weight: .black))
            .foregroundStyle(Theme.tint(state))
            .frame(width: 11, height: 11)
            .background(Color(nsColor: .windowBackgroundColor), in: Circle())
            .overlay { Circle().strokeBorder(Theme.tint(state), lineWidth: 1) }
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private func badgeView(_ badge: Badge) -> some View {
        switch badge {
        case .question:
            Text("?")
                .font(.system(size: 8, weight: .black, design: .rounded))
                .foregroundStyle(Theme.onTint)
                .frame(width: 11, height: 11)
                .background(Theme.question, in: Circle())
                .overlay { Circle().strokeBorder(Color(nsColor: .windowBackgroundColor), lineWidth: 1) }
                .accessibilityLabel("The agent asks a question")
        case .unread:
            Circle()
                .fill(.tint)
                .frame(width: 8, height: 8)
                .overlay { Circle().strokeBorder(Color(nsColor: .windowBackgroundColor), lineWidth: 1) }
                .accessibilityLabel("A new message from the agent")
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
    /// The comments with an agent message the person hasn't looked at.
    var unread: Set<ItemID> = []
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
                        MarkerPin(
                            number: index + 1, state: comment.state, isSelected: isSelected,
                            badge: MarkerPin.Badge(comment, unread: unread)
                        )
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
