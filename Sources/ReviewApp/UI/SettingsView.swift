import AppKit
import ReviewWire
import SwiftUI

struct SettingsView: View {
    let model: AppModel

    var body: some View {
        let palette = Palette(theme: model.themes.theme)
        Form {
            Section {
                HStack(spacing: 12) {
                    HavoochMark(size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(AppIdentity.appName)
                            .font(.headline)
                        Text("Version \(Version.app)")
                            .font(.caption)
                            .foregroundStyle(palette[.textSecondary])
                    }
                }
                .accessibilityElement(children: .combine)
            }
            Section {
                ThemePicker(model: model)
            } footer: {
                Text("Follow the System shows Default Light or Default Dark with the Mac's appearance. The same choice as View › Theme.")
                    .font(.caption)
                    .foregroundStyle(palette[.textSecondary])
                    .fixedSize(horizontal: false, vertical: true)
            }
            ConfigSection(config: model.config)
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
        .tint(palette[.accent])
        .preferredColorScheme(RootView.scheme(of: model.themes))
        .environment(\.palette, palette)
    }
}

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
                    model.windows.key?.problem = WindowModel.Problem(title: "The theme didn't change", reason: error.reason)
                }
            }
        )
    }
}

final class SettingsWindow {
    var open: (() -> Void)?

    var window: NSWindow? {
        NSApp.windows.first { $0.isVisible && Self.isSettings($0) }
    }

    func show() async throws(AppRefusal) {
        guard let open else { throw AppRefusal("the player's window isn't on screen to open Settings from") }
        if window == nil { open() }
        for _ in 0..<40 where window == nil {
            try? await Task.sleep(for: .milliseconds(50))
        }
        guard window != nil else { throw AppRefusal("the Settings window didn't open") }
    }

    static func isSettings(_ window: NSWindow) -> Bool {
        window.identifier?.rawValue.localizedCaseInsensitiveContains("settings") ?? false
    }
}

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

private struct ConfigSection: View {
    let config: ConfigDesk
    @Environment(\.palette) private var palette

    var body: some View {
        Section {
            LabeledContent("File") {
                Text(config.location.file.path)
                    .textSelection(.enabled)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
            LabeledContent("Status") {
                Label(
                    config.verdict.accepted ? "Applied" : "Not applied",
                    systemImage: config.verdict.accepted ? "checkmark.circle" : "exclamationmark.triangle"
                )
                .foregroundStyle(config.verdict.accepted ? palette[.textSecondary] : palette[.question])
            }
            ForEach(config.verdict.problems, id: \.description) { problem in
                Text(problem.description)
                    .font(.callout)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(config.notes, id: \.self) { note in
                Text(note)
                    .font(.callout)
                    .foregroundStyle(palette[.textSecondary])
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            Text("Settings File")
        } footer: {
            Text(
                config.verdict.accepted
                    ? "Havooch applies each save at once. Your own themes go in the themes folder beside the file."
                    : "Havooch keeps the last valid settings until the file reads. Run havooch config check after a fix."
            )
            .font(.caption)
            .foregroundStyle(palette[.textSecondary])
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}
