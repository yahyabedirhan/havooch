import SwiftUI

/// The tour's pulsing ring around the part of the window a step is about
/// (H4), from connect-flow V6. `radius` is the marked part's corner radius;
/// the ring stands `padding` points outside it, its radius grown by the
/// same amount, so it never touches the content.
struct CoachRing: ViewModifier {
    let on: Bool
    let radius: CGFloat
    var padding: CGFloat = Self.padding
    @State private var pulse = false
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// How far the ring stands outside the part it marks.
    static let padding: CGFloat = 9
    /// The ring's padding in a scrolling list, whose margin is narrower.
    static let tightPadding: CGFloat = 6

    func body(content: Content) -> some View {
        content
            .overlay {
                if on {
                    RoundedRectangle(cornerRadius: radius + padding, style: .continuous)
                        .strokeBorder(palette[.accent], lineWidth: 2)
                        .padding(-padding)
                        .shadow(color: palette[.accent].opacity(pulse ? 0.7 : 0.2), radius: pulse ? 8 : 2)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                        .onAppear {
                            guard !reduceMotion else { return }
                            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { pulse = true }
                        }
                        .onDisappear { pulse = false }
                }
            }
            // Over the parts around it, so the part beside it never covers
            // the ring.
            .zIndex(on ? 1 : 0)
    }
}

extension View {
    /// The tour's ring around this view while `on`; `radius` is the view's
    /// own corner radius.
    func coachRing(_ on: Bool, radius: CGFloat = 8, padding: CGFloat = CoachRing.padding) -> some View {
        modifier(CoachRing(on: on, radius: radius, padding: padding))
    }
}
