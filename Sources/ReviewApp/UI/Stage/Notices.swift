import ReviewCore
import SwiftUI

struct Notices: View {
    let model: WindowModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let width: CGFloat = 300
    static let most = 3

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            ForEach(model.notices.suffix(Self.most)) { notice in
                NoticeCard(notice: notice) { model.openNotice(notice.id) }
                    .pressedByKeys(in: model) { model.openNotice(notice.id) }
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
        .buttonStyle(.borderless)
        .help(help)
        .accessibilityElement(children: .combine)
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
    }

    private var help: String {
        switch notice.kind {
        case .question: "Show the question and answer it"
        case .takeover: "Show General"
        case .acknowledgement, .message: "Show the message"
        }
    }

    private var symbol: String {
        switch notice.kind {
        case .acknowledgement: "checkmark"
        case .message: "sparkles"
        case .question: "questionmark"
        case .takeover: "arrow.left.arrow.right"
        }
    }

    private var tint: Color {
        notice.kind == .question ? palette[.question] : palette[.agent]
    }
}
