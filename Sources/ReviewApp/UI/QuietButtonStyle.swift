import SwiftUI

/// The look of a quiet symbol button, in the timeline lane and on a row: no
/// chrome at rest, a soft fill and the primary colour under the pointer, and
/// a deeper fill with a small press while it's held, so it answers on the
/// press and not on the release.
struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        QuietButton(configuration: configuration)
    }

    private struct QuietButton: View {
        let configuration: ButtonStyleConfiguration
        @State private var isHovered = false
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            let isLit = isEnabled && (isHovered || configuration.isPressed)
            configuration.label
                .foregroundStyle(isLit ? .primary : .secondary)
                .background(fill, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .scaleEffect(configuration.isPressed && !reduceMotion ? 0.92 : 1)
                .opacity(isEnabled ? 1 : 0.4)
                .animation(.smooth(duration: 0.12), value: configuration.isPressed)
                .animation(.smooth(duration: 0.12), value: isHovered)
                .onHover { isHovered = $0 }
        }

        private var fill: Color {
            guard isEnabled else { return .clear }
            if configuration.isPressed { return Color.primary.opacity(0.12) }
            return isHovered ? Color.primary.opacity(0.06) : .clear
        }
    }
}
