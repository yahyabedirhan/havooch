import AppKit
import SwiftUI

/// One joined split control at the small size, on the theme's `accentFill`
/// with white text, the pair `filledButton` uses (ADR 0006): the main part
/// runs `action`, the chevron opens `menu` (L67). Drawn by hand because a
/// `Menu` with a primary action ignores the prominent fill and draws grey,
/// even in the key window.
struct SplitButton<MenuContent: View>: View {
    private let title: String
    private let helpText: String?
    private let isOn: Bool
    private let action: () -> Void
    private let menu: MenuContent
    /// The player window whose keys press the main part while it has the
    /// keyboard focus; set with `pressedByKeys(in:)`.
    private var keys: WindowModel?
    @Environment(\.palette) private var palette
    @Environment(\.isEnabled) private var environmentEnabled
    @State private var hoversMain = false
    @State private var hoversMenu = false

    static var height: CGFloat { 22 }
    static var corner: CGFloat { 6 }

    /// `title` on the main part, which runs `action`; `menu` behind the
    /// arrow; `help` as the tooltip. Off when `isEnabled` is false or the
    /// environment turns it off.
    init(
        _ title: String, help: String? = nil, isEnabled: Bool = true,
        action: @escaping () -> Void,
        @ViewBuilder menu: () -> MenuContent
    ) {
        self.title = title
        self.helpText = help
        self.isOn = isEnabled
        self.action = action
        self.menu = menu()
    }

    /// Lets Space and Return press the main part while it has the keyboard
    /// focus, as other buttons do (`View.pressedByKeys`).
    func pressedByKeys(in model: WindowModel?) -> Self {
        var copy = self
        copy.keys = model
        return copy
    }

    private var isEnabled: Bool { isOn && environmentEnabled }

    var body: some View {
        HStack(spacing: 0) {
            Button(action: action) {
                Text(title)
                    .font(.system(size: NSFont.smallSystemFontSize, weight: .medium))
                    .padding(.leading, 10)
                    .padding(.trailing, 9)
                    .frame(height: Self.height)
                    .contentShape(Rectangle())
            }
            .buttonStyle(SplitPart(palette: palette, hovers: hoversMain && isEnabled))
            .pressedByKeys(in: keys, action: action)
            .onHover { hoversMain = $0 }
            .accessibilityLabel(title)

            Rectangle()
                .fill(palette.textOnFill.opacity(0.35))
                .frame(width: 1)
                .padding(.vertical, 4)
                .accessibilityHidden(true)

            Menu {
                menu
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(palette.textOnFill)
                    .frame(width: 20, height: Self.height)
                    .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .background(palette.shade(hoversMenu && isEnabled ? 0.08 : 0))
            .onHover { hoversMenu = $0 }
            .accessibilityLabel("More")
        }
        .foregroundStyle(palette.textOnFill)
        .background(palette[.accentFill])
        .clipShape(RoundedRectangle(cornerRadius: Self.corner, style: .continuous))
        .opacity(isEnabled ? 1 : 0.45)
        .fixedSize()
        .disabled(!isOn)
        .help(helpText ?? "")
        .animation(.easeOut(duration: 0.1), value: hoversMain)
        .animation(.easeOut(duration: 0.1), value: hoversMenu)
    }
}

/// The main part: no chrome of its own, a darker fill on hover and press.
private struct SplitPart: ButtonStyle {
    let palette: Palette
    let hovers: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(palette.shade(configuration.isPressed ? 0.14 : hovers ? 0.08 : 0))
    }
}
