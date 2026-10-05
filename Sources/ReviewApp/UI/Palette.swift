import AppKit
import ReviewCore
import SwiftUI

/// The active theme's tokens as colours: the only way a view gets a colour.
/// A view reads it from the environment (`@Environment(\.palette)`), which
/// `RootView` fills from `ThemeDesk`; a theme change redraws every view.
///
/// This file is the one place in the app that makes a colour, from numbers
/// or from the system: a surface the theme sets to `system` is the native
/// macOS part. A test finds raw colours anywhere else in the views.
struct Palette: Equatable {
    let theme: ResolvedTheme

    /// The colour of `token`. A `system` token is the native colour, which
    /// follows the window's appearance; a popover's or a notice's is the
    /// window background, the solid colour nearest its material. A token
    /// no theme sets (only possible without the built-in themes) is a mid
    /// grey, so it shows and is found.
    subscript(_ token: ThemeToken) -> Color {
        if theme.isSystem(token) { return Color(nsColor: Self.systemColor(token)) }
        guard let color = theme[token] else { return Color(.sRGB, white: 0.5) }
        return Color(
            .sRGB, red: Double(color.red) / 255, green: Double(color.green) / 255, blue: Double(color.blue) / 255,
            opacity: Double(color.alpha) / 255
        )
    }

    /// `token` for AppKit, such as a text view's text colour.
    func nsColor(_ token: ThemeToken) -> NSColor {
        if theme.isSystem(token) { return Self.systemColor(token) }
        guard let color = theme[token] else { return NSColor(white: 0.5, alpha: 1) }
        return NSColor(
            srgbRed: CGFloat(color.red) / 255, green: CGFloat(color.green) / 255, blue: CGFloat(color.blue) / 255,
            alpha: CGFloat(color.alpha) / 255
        )
    }

    /// What fills a floating surface, from the back: a material, then a
    /// fill on it.
    struct Surface {
        let material: AnyShapeStyle?
        let fill: AnyShapeStyle
    }

    /// What fills a popover or a notice: when the theme sets it to
    /// `system`, the ultra-thick material under the window colour at 80%,
    /// else the token's colour alone. A bare material over a dark video
    /// turns a light window's popover grey, and its quiet words stop
    /// being readable; the window colour on it keeps them on the colour
    /// the contrast test checks, and the material still shows through.
    func surface(_ token: ThemeToken) -> Surface {
        guard theme.isSystem(token), token == .popover || token == .notice else {
            return Surface(material: nil, fill: AnyShapeStyle(self[token]))
        }
        return Surface(material: AnyShapeStyle(.ultraThickMaterial), fill: AnyShapeStyle(self[token].opacity(0.8)))
    }

    /// Whether the window is the native macOS window: its background and
    /// its toolbar are the system's, not painted.
    var isNative: Bool {
        theme.isSystem(.window)
    }

    /// The native colour of a surface token set to `system`.
    static func systemColor(_ token: ThemeToken) -> NSColor {
        switch token {
        case .field: .textBackgroundColor
        case .separator: .separatorColor
        default: .windowBackgroundColor
        }
    }

    /// The colour of a message state. A state is never told by colour
    /// alone: `StateLook` gives its glyph and its name.
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

    /// The colour of the listener's presence.
    func presence(_ presence: Presence) -> Color {
        switch presence {
        case .listening: self[.presenceListening]
        case .working: self[.presenceWorking]
        case .absent: self[.presenceAbsent]
        }
    }

    /// Before `RootView` sets the active theme: every token grey.
    static let unset = Palette(theme: ResolvedTheme(name: "", kind: .light, colors: [:]))
}

/// The palette in the environment. Written out, not with `@Entry`: the
/// Command Line Tools ship no SwiftUI macros.
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
    /// A native popover's background: the system's own popover in a
    /// native theme, the theme's `popover` colour in a painted one, so a
    /// painted window never opens a native popover.
    func popoverSurface(_ palette: Palette) -> some View {
        modifier(PopoverSurface(palette: palette))
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
