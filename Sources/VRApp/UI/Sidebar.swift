import SwiftUI

/// The review beside the video: the open video's comments as cards, in time
/// order. The selected comment's card is scrolled into view.
struct Sidebar: View {
    let model: ReviewModel

    var body: some View {
        let comments = model.comments
        VStack(spacing: 0) {
            HStack {
                Text("Comments")
                    .font(.headline)
                Spacer()
                Text("\(model.session?.queue.count ?? 0) queued")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, Theme.edge)
            .frame(height: 40)
            Divider()
            if comments.isEmpty {
                empty
            } else {
                ScrollViewReader { scroll in
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(comments) { comment in
                                CommentCard(
                                    comment: comment,
                                    picture: model.cropURL(for: comment.id) ?? model.keyframeURL(for: comment.id),
                                    isSelected: model.selection == comment.id,
                                    show: { model.showByPerson(comment.id) },
                                    edit: { (try? model.editComment(comment.id, text: $0)) != nil },
                                    delete: { try? model.deleteComment(comment.id) }
                                )
                                .id(comment.id)
                            }
                        }
                        .padding(Theme.gap)
                    }
                    .onChange(of: model.selection) { _, selected in
                        guard let selected else { return }
                        withAnimation { scroll.scrollTo(selected) }
                    }
                }
            }
        }
        .frame(width: Theme.sidebarWidth)
        .frame(maxHeight: .infinity)
        .background(.background)
    }

    private var empty: some View {
        VStack(spacing: 6) {
            Image(systemName: "text.bubble")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.secondary)
            Text("No comments yet")
                .font(.headline)
            Text("Press C to comment at the player's time, or drag on the frame to comment on a part of it.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(Theme.edge)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
