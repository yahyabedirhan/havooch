import SwiftUI
import VRReview

/// The review beside the video: the open video's comments as cards, in time
/// order, each batch as a header card above the first of its comments, with
/// the send bar under them. The selected comment's card is scrolled into
/// view.
struct Sidebar: View {
    let model: ReviewModel

    /// One card of the list.
    enum Row: Equatable, Identifiable {
        case batch(Batch)
        case comment(Comment)

        var id: String {
            switch self {
            case .batch(let batch): "batch-" + batch.id
            case .comment(let comment): comment.id
            }
        }
    }

    /// The cards for `comments` (in time order) and the batches they were
    /// sent in: each batch's header stands above the first of its comments.
    nonisolated static func rows(comments: [Comment], batches: [Batch]) -> [Row] {
        var headed: Set<String> = []
        var rows: [Row] = []
        for comment in comments {
            if let id = comment.batchID, headed.insert(id).inserted, let batch = batches.first(where: { $0.id == id }) {
                rows.append(.batch(batch))
            }
            rows.append(.comment(comment))
        }
        return rows
    }

    /// Where the batch is on its way, as its header says it.
    private func progress(of batch: Batch) -> BatchCard.Progress {
        if model.session?.isFinished(batch.id) == true { return .finished }
        return model.outbox.parcel(batch.id)?.delivery == .pending ? .pending : .taken
    }

    var body: some View {
        let comments = model.comments
        VStack(spacing: 0) {
            HStack {
                Text("Comments")
                    .font(.headline)
                Spacer()
                Text("\(comments.count)")
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
                            ForEach(Self.rows(comments: comments, batches: model.session?.batches ?? [])) { row in
                                switch row {
                                case .batch(let batch):
                                    BatchCard(batch: batch, progress: progress(of: batch))
                                case .comment(let comment):
                                    CommentCard(
                                        comment: comment,
                                        picture: model.cropURL(for: comment.id) ?? model.keyframeURL(for: comment.id),
                                        isSelected: model.selection == comment.id,
                                        hasOpenQuestion: comment.openQuestion != nil,
                                        show: { model.showByPerson(comment.id) },
                                        edit: { (try? model.editComment(comment.id, text: $0)) != nil },
                                        delete: { try? model.deleteComment(comment.id) },
                                        answer: { model.answerByPerson(comment.id, text: $0) }
                                    )
                                    .id(comment.id)
                                }
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
            Divider()
            SendBar(model: model)
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
