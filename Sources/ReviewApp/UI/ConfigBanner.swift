import SwiftUI

/// The settings notice at the top of the window (ADR 0002): what the move
/// into `config.toml` did, or the problems of a save the app didn't apply.
/// It never blocks the window or the control socket: the person reads it
/// and closes it, or `havooch config dismiss` does. A full soft fill and
/// an icon set it apart, never a coloured edge.
struct ConfigBanner: View {
    /// The window it shows in: every window shows the app's one notice.
    let model: WindowModel
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let width: CGFloat = 460

    var body: some View {
        Group {
            if let notice = model.config.notice {
                card(notice)
                    .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.top, 12)
        .frame(maxWidth: .infinity, alignment: .top)
        .animation(reduceMotion ? .easeOut(duration: 0.2) : .spring(duration: 0.3), value: model.config.notice)
    }

    private func card(_ notice: ConfigDesk.Notice) -> some View {
        let tint = notice.kind == .rejected ? palette[.question] : palette[.accent]
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: notice.kind == .rejected ? "exclamationmark.triangle" : "gearshape")
                .font(.body.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 22, height: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(notice.title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(palette[.noticeText])
                ForEach(notice.lines, id: \.self) { line in
                    Text(line)
                        .font(.callout)
                        .foregroundStyle(palette[.textSecondary])
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                model.app.dismissConfigNotice()
            } label: {
                Image(systemName: "xmark")
                    .foregroundStyle(palette[.textSecondary])
            }
            .buttonStyle(.borderless)
            .help("Close")
            .accessibilityLabel("Close the settings notice")
            .pressedByKeys(in: model) { model.app.dismissConfigNotice() }
        }
        .padding(12)
        .frame(width: Self.width)
        .popoverChrome(
            RoundedRectangle(cornerRadius: 12, style: .continuous), surface: palette.surface(.notice), border: palette[.popoverBorder]
        )
        .accessibilityElement(children: .contain)
    }
}
