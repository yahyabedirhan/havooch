import SwiftUI
import VRReview

/// The window's trailing column, on the window's background: the queue
/// on top, in time order, then the sent comments, grouped by batch with
/// the newest batch first. A batch's group starts with its head and the
/// agent's messages for the whole batch. Space and thin dividers part the
/// groups. At its foot, as tall as the transport bar, the send bar: the
/// listener's presence, the queued count and Send.
struct Sidebar: View {
    let model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let review = model.desk.open
        let queue = review?.queue ?? []
        let batches = review?.batches ?? []
        VStack(alignment: .leading, spacing: 0) {
            Group {
                if queue.isEmpty, batches.isEmpty {
                    hint
                } else {
                    list(review: review, queue: queue, batches: batches)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            Divider()
            footer(queued: queue.count)
        }
    }

    private func list(review: Review?, queue: [Comment], batches: [Batch]) -> some View {
        ScrollViewReader { scroller in
            ScrollView {
                // Not a lazy stack: a comment keeps its id as it moves from
                // the queue into its batch, and a lazy stack went on
                // showing the row it had built for the queue.
                VStack(alignment: .leading, spacing: 0) {
                    section {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("Queue")
                                .font(.headline)
                            if !queue.isEmpty {
                                Text("\(queue.count)")
                                    .font(.callout.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, Theme.edge)
                    } rows: {
                        ForEach(queue) { comment in
                            card(comment)
                        }
                        if queue.isEmpty {
                            Text("Nothing queued")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, Theme.edge)
                        }
                    }
                    ForEach(batches.reversed()) { batch in
                        let sent = review?.comments.filter { $0.batch == batch.id } ?? []
                        Divider()
                            .padding(.horizontal, Theme.edge)
                        section {
                            BatchHeader(batch: batch, comments: sent, standing: model.listener.standing(of: batch.id))
                                .padding(.horizontal, Theme.edge - 8)
                        } rows: {
                            if !batch.thread.isEmpty {
                                BatchCard(batch: batch)
                                    .padding(.horizontal, Theme.edge - 8)
                            }
                            ForEach(sent) { comment in
                                card(comment)
                            }
                        }
                    }
                }
                .padding(.bottom, 8)
            }
            // The comment in focus is brought into sight: a click on its
            // marker or on a notice may name a row far down the list.
            .onChange(of: model.selection) { _, selected in
                guard let selected else { return }
                if reduceMotion {
                    scroller.scrollTo(selected)
                } else {
                    withAnimation(.easeOut(duration: 0.2)) { scroller.scrollTo(selected) }
                }
            }
        }
    }

    /// One group of the list: its header, then its rows close together.
    private func section<Header: View, Rows: View>(
        @ViewBuilder header: () -> Header, @ViewBuilder rows: () -> Rows
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            header()
            VStack(alignment: .leading, spacing: 6) {
                rows()
            }
        }
        .padding(.top, 14)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The send bar: who listens on the left, then the queued count and Send.
    private func footer(queued: Int) -> some View {
        HStack(spacing: 10) {
            PresencePill(listener: model.listener)
            Spacer(minLength: 8)
            if queued > 0 {
                Text("\(queued) queued")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Button {
                model.sendBatchForPerson()
            } label: {
                Label("Send ⌘↩", systemImage: "paperplane.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(!model.canSend)
            .help("Send the queued comments to the listener as one batch (Command-Return)")
            .accessibilityLabel("Send comments")
        }
        .padding(.horizontal, Theme.edge)
        .frame(height: Theme.footerHeight)
    }

    /// A comment's row, full width, inset so its own 8 points of padding
    /// line its text up with the headers at the bar's edge.
    private func card(_ comment: Comment) -> some View {
        CommentCard(model: model, comment: comment, keyframe: model.desk.keyframe(of: comment.id))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.edge - 8)
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
