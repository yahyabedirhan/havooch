import ReviewCore
import SwiftUI

/// One thread's pin: its number, drawn by its state. A queued thread is
/// hollow; every later state fills the pin with its
/// colour, and a state the agent set adds its glyph at the pin's foot. A
/// badge at its head says the agent waits for an answer, or said something
/// the person hasn't looked at. It heads the thread in the rail and its
/// region on the frame; the player bar's timeline has `ThreadPin`.
struct MarkerPin: View {
    /// What the agent left on a thread for the person.
    enum Badge: Equatable {
        /// A message the person hasn't looked at.
        case unread
        /// A question that waits for an answer.
        case question

        /// The badge of `thread`: an open question comes before an
        /// unread message, since the agent waits for it.
        init?(_ thread: ReviewThread, unread: Set<ThreadID>) {
            if thread.openQuestion != nil {
                self = .question
            } else if unread.contains(thread.id) {
                self = .unread
            } else {
                return nil
            }
        }
    }

    let number: Int
    let state: MessageState
    var isSelected = false
    var badge: Badge?

    static let size: CGFloat = 18
    @Environment(\.palette) private var palette
    /// How far a badge or a state glyph stands out from the pin.
    static let overhang: CGFloat = 4

    var body: some View {
        Text("\(number)")
            .font(.system(size: number > 99 ? 8 : 10.5, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(isHollow ? palette[.textPrimary] : palette[.textOnAccent])
            .frame(width: Self.size, height: Self.size)
            .background(isHollow ? palette[.bar] : palette.state(state), in: Circle())
            .overlay {
                Circle().strokeBorder(
                    isSelected ? palette[.accent] : (isHollow ? palette[.textSecondary] : palette.state(state)),
                    lineWidth: isSelected ? 2 : 1.5
                )
            }
            .background {
                if isSelected {
                    Circle().fill(palette[.accent].opacity(0.28)).padding(-4)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if let glyph = StateLook.pinGlyph(state) {
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
            .foregroundStyle(palette.state(state))
            .frame(width: 11, height: 11)
            .background(palette[.bar], in: Circle())
            .overlay { Circle().strokeBorder(palette.state(state), lineWidth: 1) }
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private func badgeView(_ badge: Badge) -> some View {
        switch badge {
        case .question:
            Text("?")
                .font(.system(size: 8, weight: .black, design: .rounded))
                .foregroundStyle(palette[.textOnAccent])
                .frame(width: 11, height: 11)
                .background(palette[.question], in: Circle())
                .overlay { Circle().strokeBorder(palette[.bar], lineWidth: 1) }
                .accessibilityLabel("The agent asks a question")
        case .unread:
            Circle()
                .fill(palette[.agent])
                .frame(width: 8, height: 8)
                .overlay { Circle().strokeBorder(palette[.bar], lineWidth: 1) }
                .accessibilityLabel("A new message from the agent")
        }
    }

    private var isHollow: Bool {
        state == .queued
    }
}
