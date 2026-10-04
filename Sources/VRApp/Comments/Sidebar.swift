import SwiftUI
import VRReview

/// The window's trailing column: the queue on top, in time order, with its
/// count and the Send button, then the sent comments, grouped by batch
/// with the newest batch first. A batch's group starts with its head and
/// the agent's messages for the whole batch.
struct Sidebar: View {
    let model: AppModel

    var body: some View {
        let review = model.desk.open
        let queue = review?.queue ?? []
        let batches = review?.batches ?? []
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
                Button {
                    model.sendBatchForPerson()
                } label: {
                    Label("Send ⌘↩", systemImage: "paperplane.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(!model.canSend)
                .help("Send the queued comments to the listener as one batch (Command-Return)")
                .accessibilityLabel("Send comments")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            Divider()
            if queue.isEmpty, batches.isEmpty {
                hint
            } else {
                ScrollViewReader { scroller in
                ScrollView {
                    // Not a lazy stack: a comment keeps its id as it moves from
                    // the queue into its batch, and a lazy stack went on
                    // showing the card it had built for the queue.
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(queue) { comment in
                            card(comment)
                        }
                        if queue.isEmpty {
                            Text("Nothing queued")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 4)
                        }
                        ForEach(batches.reversed()) { batch in
                            let sent = review?.comments.filter { $0.batch == batch.id } ?? []
                            BatchHeader(batch: batch, comments: sent, standing: model.listener.standing(of: batch.id))
                                .padding(.top, 10)
                            if !batch.thread.isEmpty {
                                BatchCard(batch: batch)
                            }
                            ForEach(sent) { comment in
                                card(comment)
                            }
                        }
                    }
                    .padding(8)
                }
                // The comment in focus is brought into sight: a click on its
                // marker or on a notice may name a card far down the list.
                .onChange(of: model.selection) { _, selected in
                    guard let selected else { return }
                    withAnimation(.easeOut(duration: 0.2)) { scroller.scrollTo(selected) }
                }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func card(_ comment: Comment) -> some View {
        CommentCard(model: model, comment: comment, keyframe: model.desk.keyframe(of: comment.id))
            .id(comment.id)
    }

    /// What an empty sidebar says: how a comment is made.
    private var hint: some View {
        VStack(spacing: 8) {
            Image(systemName: "bubble.left")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.tertiary)
            Text(model.player.video == nil ? "No video is open" : "No comments yet")
                .font(.callout.weight(.medium))
            if model.player.video != nil {
                Text("Pause on a moment and press Return or C to comment on it, or drag on the frame to comment on a part of it.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
