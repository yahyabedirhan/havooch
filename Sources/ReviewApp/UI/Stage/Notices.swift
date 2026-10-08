import ReviewCore
import SwiftUI

/// The brief notices in the stage's top-right corner: what the agent just
/// said, under a line that names the thread (`#3 · Claude Code`). Every
/// notice fades by itself after a few seconds, a question too: the question
/// stays open on its thread, where the person answers it (L28). A click
/// opens the thread it's on.
struct Notices: View {
    let model: WindowModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let width: CGFloat = 300
    /// The most notices shown at once: the newest ones.
    static let most = 3

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            ForEach(model.notices.suffix(Self.most)) { notice in
                NoticeCard(notice: notice) { model.openNotice(notice.id) }
                    .pressedByKeys(in: model) { model.openNotice(notice.id) }
                    // In from the edge, and out as a fade.
                    .transition(.asymmetric(
                        insertion: reduceMotion ? .opacity : .move(edge: .trailing).combined(with: .opacity),
                        removal: .opacity
                    ))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .animation(reduceMotion ? .easeOut(duration: 0.2) : .spring(duration: 0.3), value: model.notices)
    }
}

/// One notice: who said what, on which thread.
private struct NoticeCard: View {
    let notice: Notice
    let open: () -> Void
    @Environment(\.palette) private var palette

    var body: some View {
        Button(action: open) {
            HStack(alignment: .top, spacing: 10) {
                AgentAvatar(agent: notice.knownAgent, size: 22, symbol: symbol, fill: tint)
                VStack(alignment: .leading, spacing: 3) {
                    Text(notice.title)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(palette[.noticeText])
                    Text(notice.text)
                        .font(.callout)
                        .foregroundStyle(palette[.textSecondary])
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                    if let hint = notice.hint {
                        Text(hint)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(tint)
                            .padding(.top, 1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
            .frame(width: Notices.width)
            .popoverChrome(
                shape, surface: palette.surface(.notice),
                border: notice.kind == .question ? tint.opacity(0.7) : palette[.popoverBorder],
                lineWidth: notice.kind == .question ? 1.5 : 1
            )
            .contentShape(shape)
        }
        // A native borderless button: the card dims while pressed and
        // takes the focus ring under keyboard navigation.
        .buttonStyle(.borderless)
        .help(notice.kind == .question ? "Show the question and answer it" : "Show the message")
        .accessibilityElement(children: .combine)
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
    }

    /// The symbol an unknown agent's notice shows.
    private var symbol: String {
        switch notice.kind {
        case .acknowledgement: "checkmark"
        case .message: "sparkles"
        case .question: "questionmark"
        }
    }

    private var tint: Color {
        notice.kind == .question ? palette[.question] : palette[.agent]
    }
}
