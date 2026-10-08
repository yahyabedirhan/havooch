import SwiftUI

/// A command Havooch runs in the login shell, shown in full before it runs
/// (connect-view V3): the line on top, then a footer bar under a hairline
/// with where it runs, a copy icon and Run Command. While it runs, the
/// line dims and the footer holds the live log line and Cancel instead.
/// It has the shape of `CopyBox`.
struct RunBox: View {
    let text: String
    let running: Bool
    /// The last line the running command wrote.
    var log = ""
    /// Whether Run Command can start it now: false while another command runs.
    var canRun = true
    /// The player window whose key monitor a focused button tells; nil
    /// outside a player window.
    let keysWindow: WindowModel?
    let run: () -> Void
    /// Cancel in the footer while it runs; none without it.
    var cancel: (() -> Void)?

    @State private var copied = false
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(text)
                .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                .lineSpacing(2)
                .foregroundStyle(running ? palette[.textSecondary] : palette[.textPrimary])
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 11)
                .padding(.vertical, 10)
            Rectangle().fill(palette[.separator]).frame(height: 0.5)
            HStack(spacing: 6) {
                if running { runningFooter } else { idleFooter }
            }
            .foregroundStyle(palette[.textTertiary])
            .padding(.leading, 11)
            .padding(.trailing, 6)
            .frame(height: 30)
            .background(palette[.well])
        }
        .background(palette[.field].opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(palette[.separator], lineWidth: 0.5))
    }

    @ViewBuilder private var idleFooter: some View {
        Image(systemName: "terminal").font(.system(size: 10, weight: .medium))
        Text("Login shell").font(.caption2.weight(.medium))
        Spacer(minLength: 6)
        Button(action: copy) {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(copied ? palette[.stateDone] : palette[.textSecondary])
                .frame(width: 24, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pressedByKeys(in: keysWindow, action: copy)
        .help(copied ? "Copied" : "Copy the command to run it yourself")
        .accessibilityLabel(copied ? "Copied" : "Copy Command")
        Button(action: run) {
            pill(Label("Run Command", systemImage: "play.fill").labelStyle(.titleAndIcon), palette[.accent])
        }
        .buttonStyle(.plain)
        .disabled(!canRun)
        .opacity(canRun ? 1 : 0.5)
        .pressedByKeys(in: keysWindow) { if canRun { run() } }
        .help(canRun ? "Run this command in your login shell" : "Another install is running")
    }

    @ViewBuilder private var runningFooter: some View {
        ProgressView().controlSize(.mini)
        Text(log)
            .font(.system(size: 10.5, design: .monospaced))
            .foregroundStyle(palette[.textSecondary])
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
            .help(log)
        if let cancel {
            Button(action: cancel) {
                pill(Text("Cancel"), palette[.textSecondary])
            }
            .buttonStyle(.plain)
            .pressedByKeys(in: keysWindow, action: cancel)
        }
    }

    /// A footer button's label: semibold caption on a soft fill of `colour`.
    private func pill(_ label: some View, _ colour: Color) -> some View {
        label
            .font(.caption.weight(.semibold))
            .foregroundStyle(colour)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(colour.opacity(0.12), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .fixedSize()
            .contentShape(Rectangle())
    }

    private func copy() {
        CopyBox.copy(text)
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            copied = false
        }
    }
}
