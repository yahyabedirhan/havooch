import AppKit
import ReviewCore
import SwiftUI

struct Palette: Equatable {
    let theme: ResolvedTheme

    subscript(_ token: ThemeToken) -> Color {
        if theme.isSystem(token) { return Color(nsColor: Self.systemColor(token)) }
        guard let color = theme[token] else { return Color(.sRGB, white: 0.5) }
        return Color(
            .sRGB, red: Double(color.red) / 255, green: Double(color.green) / 255, blue: Double(color.blue) / 255,
            opacity: Double(color.alpha) / 255
        )
    }

    func nsColor(_ token: ThemeToken) -> NSColor {
        if theme.isSystem(token) { return Self.systemColor(token) }
        guard let color = theme[token] else { return NSColor(white: 0.5, alpha: 1) }
        return NSColor(
            srgbRed: CGFloat(color.red) / 255, green: CGFloat(color.green) / 255, blue: CGFloat(color.blue) / 255,
            alpha: CGFloat(color.alpha) / 255
        )
    }

    struct Surface {
        let material: AnyShapeStyle?
        let fill: AnyShapeStyle
    }

    func surface(_ token: ThemeToken) -> Surface {
        guard theme.isSystem(token), token == .popover || token == .notice else {
            return Surface(material: nil, fill: AnyShapeStyle(self[token]))
        }
        return Surface(material: AnyShapeStyle(.ultraThickMaterial), fill: AnyShapeStyle(self[token].opacity(0.8)))
    }

    var isNative: Bool {
        theme.isSystem(.window)
    }

    static func systemColor(_ token: ThemeToken) -> NSColor {
        switch token {
        case .field: .textBackgroundColor
        case .separator: .separatorColor
        default: .windowBackgroundColor
        }
    }

    var focusRing: Color {
        Color(nsColor: .keyboardFocusIndicatorColor)
    }

    var textOnFill: Color {
        Color(.sRGB, white: 1, opacity: 1)
    }

    func shade(_ amount: Double) -> Color {
        Color(.sRGB, white: 0, opacity: amount)
    }

    func state(_ state: MessageState) -> Color {
        switch state {
        case .queued: self[.stateQueued]
        case .sent: self[.stateSent]
        case .acknowledged: self[.stateAcknowledged]
        case .working: self[.stateWorking]
        case .done: self[.stateDone]
        case .failed: self[.stateFailed]
        }
    }

    func presence(_ presence: Presence) -> Color {
        switch presence {
        case .listening: self[.presenceListening]
        case .working: self[.presenceWorking]
        case .absent: self[.presenceAbsent]
        }
    }

    static let unset = Palette(theme: ResolvedTheme(name: "", kind: .light, colors: [:]))
}

private struct PaletteKey: EnvironmentKey {
    static let defaultValue = Palette.unset
}

extension EnvironmentValues {
    var palette: Palette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
}

extension View {
    func popoverSurface(_ palette: Palette) -> some View {
        modifier(PopoverSurface(palette: palette))
    }

    func filledButton(_ palette: Palette) -> some View {
        buttonStyle(.borderedProminent).tint(palette[.accentFill])
    }
}

private struct PopoverSurface: ViewModifier {
    let palette: Palette

    func body(content: Content) -> some View {
        if palette.theme.isSystem(.popover) {
            content
        } else {
            content.presentationBackground(palette[.popover])
        }
    }
}
