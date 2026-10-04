import SwiftUI

/// The notices of agent messages at the top right of the stage: the newest
/// few, each gone by itself after a moment. A click shows the comment the
/// message is on. Opaque, in the window's own colours, so it reads over the
/// black stage in light and dark.
struct NoticeStack: View {
    let notices: [Notice]
    let open: (Notice) -> Void

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            ForEach(notices.suffix(Notice.shown)) { notice in
                NoticeToast(notice: notice)
                    .onTapGesture { open(notice) }
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .padding(Theme.edge)
        .animation(.easeOut(duration: 0.2), value: notices)
    }
}

private struct NoticeToast: View {
    let notice: Notice

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: Theme.glyph(for: notice.message))
                .foregroundStyle(Theme.colour(for: notice.message))
            VStack(alignment: .leading, spacing: 2) {
                Text(notice.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(notice.message.text)
                    .font(.callout)
                    .lineLimit(3)
            }
        }
        .padding(10)
        .frame(width: 280, alignment: .leading)
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: Theme.cardCorner))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardCorner).strokeBorder(.separator, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.35), radius: 8, y: 2)
        .contentShape(RoundedRectangle(cornerRadius: Theme.cardCorner))
        .help(notice.commentID == nil ? "A message for the full batch" : "Show this comment")
        .accessibilityElement(children: .combine)
    }
}
