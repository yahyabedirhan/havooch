import AppKit
import ReviewCore
import SwiftUI

/// The active theme's tokens as colours: the only way a view gets a colour.
/// A view reads it from the environment (`@Environment(\.palette)`), which
/// `RootView` fills from `ThemeDesk`; a theme change redraws every view.
///
/// This file is the one place in the app that makes a colour from numbers.
/// A test finds raw colours anywhere else in the views.
struct Palette: Equatable {
    let theme: ResolvedTheme

    /// The colour of `token`. A token no theme sets (only possible without
    /// the built-in themes) is a mid grey, so it shows and is found.
    subscript(_ token: ThemeToken) -> Color {
        guard let color = theme[token] else { return Color(.sRGB, white: 0.5) }
        return Color(
            .sRGB, red: Double(color.red) / 255, green: Double(color.green) / 255, blue: Double(color.blue) / 255,
            opacity: Double(color.alpha) / 255
        )
    }

    /// `token` for AppKit, such as a text view's text colour.
    func nsColor(_ token: ThemeToken) -> NSColor {
        guard let color = theme[token] else { return NSColor(white: 0.5, alpha: 1) }
        return NSColor(
            srgbRed: CGFloat(color.red) / 255, green: CGFloat(color.green) / 255, blue: CGFloat(color.blue) / 255,
            alpha: CGFloat(color.alpha) / 255
        )
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

/// Gives the window the appearance of a pinned theme's kind, so the title
/// bar, the toolbar and the system's controls match a pinned theme that
/// differs from the system appearance. With no pin (`kind` nil) the window
/// inherits the app's appearance, which the theme follows already.
struct WindowAppearance: NSViewRepresentable {
    let kind: ThemeKind?

    func makeNSView(context: Context) -> Probe {
        Probe()
    }

    func updateNSView(_ view: Probe, context: Context) {
        view.kind = kind
    }

    final class Probe: NSView {
        var kind: ThemeKind? {
            didSet { apply() }
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            apply()
        }

        /// SwiftUI may set the window's appearance back when the app's
        /// appearance changes (a screenshot in the other appearance): a
        /// pinned kind is set again.
        override func viewDidChangeEffectiveAppearance() {
            super.viewDidChangeEffectiveAppearance()
            apply()
        }

        private func apply() {
            guard let window else { return }
            let name: NSAppearance.Name? = kind.map { $0 == .dark ? .darkAqua : .aqua }
            guard window.appearance?.name != name else { return }
            window.appearance = name.flatMap(NSAppearance.init(named:))
        }
    }
}
