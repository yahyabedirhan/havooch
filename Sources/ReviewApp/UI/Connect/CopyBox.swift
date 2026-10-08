import AppKit
import SwiftUI

/// A command or a prompt to copy (I5): the text on top at full width, then
/// a footer bar under a hairline with what it is and its Copy button.
/// Copying changes no state in the app (G6): the button says "Copied" for
/// a moment, and that is all.
struct CopyBox: View {
    /// What the box holds: a command for a terminal, or a prompt for an agent.
    enum Kind {
        case command, prompt
    }

    let text: String
    var kind: Kind = .command

    @State private var copied = false
    @Environment(\.palette) private var palette

    var body: some View {
        let mono = kind == .command
        VStack(alignment: .leading, spacing: 0) {
            Text(text)
                .font(mono ? .system(size: 11.5, weight: .medium, design: .monospaced) : .body)
                .lineSpacing(mono ? 2 : 1)
                .foregroundStyle(palette[.textPrimary])
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 11)
                .padding(.vertical, 10)
            Rectangle().fill(palette[.separator]).frame(height: 0.5)
            HStack(spacing: 6) {
                Image(systemName: mono ? "terminal" : "text.bubble")
                    .font(.system(size: 10, weight: .medium))
                Text(mono ? "Terminal" : "Prompt")
                    .font(.caption2.weight(.medium))
                Spacer(minLength: 6)
                Button(action: copy) {
                    Label(copied ? "Copied" : (mono ? "Copy Command" : "Copy Prompt"), systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.caption.weight(.semibold))
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(copied ? palette[.stateDone] : palette[.accent])
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            (copied ? palette[.stateDone] : palette[.accent]).opacity(copied ? 0.14 : 0.12),
                            in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                        )
                        .fixedSize()
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(mono ? "Copy the command" : "Copy the prompt")
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

    private func copy() {
        Self.copy(text)
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            copied = false
        }
    }

    /// Puts `text` on the pasteboard.
    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
