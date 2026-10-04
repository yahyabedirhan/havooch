import ReviewCore
import SwiftUI

/// The rail beside the stage: the comments as cards in time order, then the
/// send bar.
struct RailView: View {
    let model: AppModel

    var body: some View {
        let comments = model.comments
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("Queue")
                    .font(.headline)
                if !comments.isEmpty {
                    Text("\(comments.count)")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                        .accessibilityLabel("\(comments.count) comments")
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            if comments.isEmpty {
                empty
            } else {
                cards(comments)
            }
            SendBar()
        }
    }

    private func cards(_ comments: [Comment]) -> some View {
        ScrollViewReader { scroll in
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(Array(comments.enumerated()), id: \.element.id) { index, comment in
                        CommentCard(model: model, comment: comment, number: index + 1)
                            .id(comment.id)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
            .onChange(of: model.selection) { _, selection in
                guard let selection else { return }
                withAnimation(.easeInOut(duration: 0.2)) { scroll.scrollTo(selection) }
            }
        }
    }

    private var empty: some View {
        VStack(spacing: 8) {
            Image(systemName: "text.bubble")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(.tertiary)
                .padding(.bottom, 2)
            Text("No comments yet")
                .font(.headline)
            Text("Press C to comment on the moment you're watching, or drag on the frame to comment on a part of it. Comments queue here, then go to your agent as one batch.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
