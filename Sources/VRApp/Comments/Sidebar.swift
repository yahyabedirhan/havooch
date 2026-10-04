import SwiftUI
import VRReview

/// The window's trailing column: the queue, in time order, with its count.
struct Sidebar: View {
    let model: AppModel

    var body: some View {
        let queue = model.desk.open?.queue ?? []
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text("QUEUE")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                if !queue.isEmpty {
                    Text("\(queue.count)")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(.quaternary, in: Capsule())
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            Divider()
            if queue.isEmpty {
                hint
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(queue) { comment in
                            CommentCard(model: model, comment: comment, keyframe: model.desk.keyframe(of: comment.id))
                        }
                    }
                    .padding(8)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// What an empty queue says: how a comment is made.
    private var hint: some View {
        VStack(spacing: 8) {
            Image(systemName: "bubble.left")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.tertiary)
            Text(model.player.video == nil ? "No video is open" : "No comments yet")
                .font(.callout.weight(.medium))
            if model.player.video != nil {
                Text("Pause on a moment and press Return or C to comment on it.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
