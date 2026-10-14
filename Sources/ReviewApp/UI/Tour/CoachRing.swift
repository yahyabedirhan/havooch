import SwiftUI

struct CoachRing: ViewModifier {
    let on: Bool
    let radius: CGFloat
    var padding: CGFloat = Self.padding
    @State private var pulse = false
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let padding: CGFloat = 9
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
            .zIndex(on ? 1 : 0)
    }
}

extension View {
    func coachRing(_ on: Bool, radius: CGFloat = 8, padding: CGFloat = CoachRing.padding) -> some View {
        modifier(CoachRing(on: on, radius: radius, padding: padding))
    }
}
