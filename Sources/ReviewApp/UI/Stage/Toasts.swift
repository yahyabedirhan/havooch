import ReviewCore
import SwiftUI

/// The brief notices in the stage's top-right corner: what the agent just
/// said. A message goes by itself after a few seconds; a question stays
/// until it's clicked or answered. A click selects the comment it's about.
struct Toasts: View {
    let model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let width: CGFloat = 300
    /// The most notices shown at once: the newest ones.
    static let most = 3

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            ForEach(model.notices.suffix(Self.most)) { notice in
                Toast(notice: notice, number: number(of: notice)) { model.openNotice(notice.id) }
                    .transition(reduceMotion ? .opacity : .move(edge: .trailing).combined(with: .opacity))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .animation(reduceMotion ? .easeOut(duration: 0.2) : .spring(duration: 0.3), value: model.notices)
    }

    /// The number of the comment a notice is about, as on its marker.
    private func number(of notice: Notice) -> Int? {
        guard case .comment(let id) = notice.subject else { return nil }
        return model.comments.firstIndex { $0.id == id }.map { $0 + 1 }
    }
}

/// One notice: who said what, about which comment.
private struct Toast: View {
    let notice: Notice
    let number: Int?
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.onTint)
                    .frame(width: 22, height: 22)
                    .background(tint, in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(notice.title(number: number))
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(notice.text)
                        .font(.callout)
                        .foregroundStyle(.secondary)
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
            .frame(width: Toasts.width)
            // A solid surface, as the comment box: words over a video stay readable.
            .background(Color(nsColor: .windowBackgroundColor), in: shape)
            .overlay { shape.strokeBorder(notice.kind == .question ? AnyShapeStyle(tint.opacity(0.7)) : AnyShapeStyle(.white.opacity(0.16)), lineWidth: notice.kind == .question ? 1.5 : 1) }
            .shadow(color: .black.opacity(0.45), radius: 14, y: 5)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .help(notice.kind == .question ? "Show the question and answer it" : "Show the comment")
        .accessibilityElement(children: .combine)
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
    }

    private var symbol: String {
        switch notice.kind {
        case .acknowledgement: "checkmark"
        case .message: "sparkles"
        case .question: "questionmark"
        }
    }

    private var tint: Color {
        notice.kind == .question ? Theme.question : Theme.agent
    }
}
