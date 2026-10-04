import SwiftUI
import VRReview

/// The window's trailing column: the queue on top, in time order, with its
/// count and the Send button, then the sent comments, grouped by batch
/// with the newest batch first.
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
                            BatchHeader(batch: batch, standing: model.listener.standing(of: batch.id))
                                .padding(.top, 10)
                            ForEach(review?.comments.filter { $0.batch == batch.id } ?? []) { comment in
                                card(comment)
                            }
                        }
                    }
                    .padding(8)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func card(_ comment: Comment) -> some View {
        CommentCard(model: model, comment: comment, keyframe: model.desk.keyframe(of: comment.id))
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

/// The head of one batch's group: its number, when it was sent, and where
/// it stands on its way to the listener.
private struct BatchHeader: View {
    let batch: Batch
    let standing: ListenerLedger.Standing

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text("BATCH \(batch.id.number.map(String.init) ?? batch.id.rawValue)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(batch.sentAt, style: .time)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            Label(Self.words(standing), systemImage: Self.symbol(standing))
                .font(.caption)
                .foregroundStyle(standing == .pending ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
        }
        .padding(.horizontal, 6)
        .accessibilityElement(children: .combine)
    }

    static func words(_ standing: ListenerLedger.Standing) -> String {
        switch standing {
        case .pending: "Waiting for a listener"
        case .taken: "Delivered to the listener"
        case .finished: "Finished"
        }
    }

    private static func symbol(_ standing: ListenerLedger.Standing) -> String {
        switch standing {
        case .pending: "hourglass"
        case .taken: "checkmark.circle"
        case .finished: "checkmark.circle.fill"
        }
    }
}
