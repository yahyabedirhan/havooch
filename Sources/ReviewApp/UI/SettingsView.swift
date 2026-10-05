import AppKit
import SwiftUI

/// The Settings window (⌘,, L42): the theme picker, the same choice as
/// View › Theme and `video-review theme set`. It takes the pinned theme's
/// appearance, as the player's window does, and the theme's accent.
struct SettingsView: View {
    let model: AppModel

    var body: some View {
        let palette = Palette(theme: model.themes.theme)
        Form {
            Section {
                ThemePicker(model: model)
            } footer: {
                Text("Follow the System shows Default Light or Default Dark with the Mac's appearance. The same choice as View › Theme.")
                    .font(.caption)
                    .foregroundStyle(palette[.textSecondary])
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        // One short section: the window fits it, with nothing to scroll.
        .scrollDisabled(true)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
        .tint(palette[.accent])
        .preferredColorScheme(RootView.scheme(of: model.themes))
        .environment(\.palette, palette)
    }
}

/// Follow the system appearance, or pin one theme: in View › Theme and in
/// Settings. A choice that fails says why in the player's window.
struct ThemePicker: View {
    let model: AppModel

    var body: some View {
        Picker("Theme", selection: selection) {
            Text("Follow the System").tag(ThemeDesk.system)
            Divider()
            ForEach(model.themes.catalog.names, id: \.self) { name in
                Text(name).tag(name)
            }
        }
    }

    private var selection: Binding<String> {
        Binding(
            get: { model.themes.pinned ?? ThemeDesk.system },
            set: { name in
                do throws(AppRefusal) {
                    _ = try model.setTheme(name)
                } catch {
                    model.problem = AppModel.Problem(title: "The theme didn't change", reason: error.reason)
                }
            }
        )
    }
}

/// The Settings window for app control: `screenshot --window settings`
/// opens it as ⌘, does and finds it. SwiftUI opens Settings only from a
/// view (`openSettings`), so the player's window hands its action over
/// (`SettingsOpener`).
final class SettingsWindow {
    /// Opens Settings; set once the player's window is on screen.
    var open: (() -> Void)?

    /// The Settings window while it's on screen.
    var window: NSWindow? {
        NSApp.windows.first { $0.isVisible && Self.isSettings($0) }
    }

    /// Opens Settings and waits, up to two seconds, until it's on screen.
    func show() async throws(AppRefusal) {
        guard let open else { throw AppRefusal("the player's window isn't on screen to open Settings from") }
        if window == nil { open() }
        for _ in 0..<40 where window == nil {
            try? await Task.sleep(for: .milliseconds(50))
        }
        guard window != nil else { throw AppRefusal("the Settings window didn't open") }
    }

    /// Whether `window` is SwiftUI's Settings window, whose identifier
    /// names it.
    static func isSettings(_ window: NSWindow) -> Bool {
        window.identifier?.rawValue.localizedCaseInsensitiveContains("settings") ?? false
    }
}

/// Hands SwiftUI's `openSettings` to `SettingsWindow`, from a view in the
/// player's window.
struct SettingsOpener: ViewModifier {
    let settings: SettingsWindow
    @Environment(\.openSettings) private var openSettings

    func body(content: Content) -> some View {
        content.onAppear {
            let action = openSettings
            settings.open = { action() }
        }
    }
}
