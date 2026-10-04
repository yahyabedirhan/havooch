import ReviewCore
import SwiftUI

/// The rail beside the stage: the queue on top, then each batch, newest
/// first, with the agent's messages about it and its comments as cards in
/// time order, then the send bar.
struct RailView: View {
    let model: AppModel

    /// One group of cards: the queue, or a batch.
    struct CardGroup: Equatable, Identifiable {
        /// The batch; nil for the queue.
        var batch: Batch?
        /// The group's comments in time order, each with its number in
        /// time order among all the video's comments, as on its marker.
        var cards: [Card]

        var id: String { batch?.id.text ?? "queue" }
    }

    struct Card: Equatable, Identifiable {
        var number: Int
        var comment: Comment

        var id: ItemID { comment.id }
    }

    /// The rail's groups for `comments` (in time order) and `batches` (in
    /// the order sent): the queue first, also when it's empty, then the
    /// batches from the newest to the oldest.
    static func groups(comments: [Comment], batches: [Batch]) -> [CardGroup] {
        let cards = comments.enumerated().map { Card(number: $0.offset + 1, comment: $0.element) }
        let queue = CardGroup(batch: nil, cards: cards.filter { $0.comment.batchID == nil })
        return [queue] + batches.reversed().map { batch in
            CardGroup(batch: batch, cards: cards.filter { $0.comment.batchID == batch.id })
        }
    }

    /// What a batch's header says beside its time: how many comments, and
    /// how many of them are finished once one is.
    static func progress(of comments: [Comment]) -> String {
        let finished = comments.count { $0.state.isFinal }
        if finished > 0 { return "\(finished) of \(comments.count) done" }
        return "\(comments.count) comment\(comments.count == 1 ? "" : "s")"
    }

    var body: some View {
        let groups = Self.groups(comments: model.comments, batches: model.batches)
        VStack(spacing: 0) {
            if model.comments.isEmpty {
                header("Queue", count: 0)
                empty
            } else {
                cards(groups)
            }
            SendBar(model: model)
        }
    }

    private func cards(_ groups: [CardGroup]) -> some View {
        ScrollViewReader { scroll in
            ScrollView {
                // Not lazy: a card that moves from the queue to its batch
                // must be drawn again in its new state, and a review has
                // tens of comments, not thousands.
                VStack(spacing: 8) {
                    ForEach(groups) { group in
                        VStack(spacing: 8) {
                            if let batch = group.batch {
                                batchHeader(batch, group.cards.map(\.comment))
                                if !batch.messages.isEmpty { batchMessages(batch) }
                            } else {
                                header("Queue", count: group.cards.count)
                                if group.cards.isEmpty { nothingQueued }
                            }
                            ForEach(group.cards) { card in
                                CommentCard(model: model, comment: card.comment, number: card.number)
                                    .id(card.id)
                                    .padding(.horizontal, 12)
                            }
                        }
                    }
                }
                .padding(.bottom, 12)
            }
            .onChange(of: model.selection) { _, selection in
                guard let selection else { return }
                withAnimation(.easeInOut(duration: 0.2)) { scroll.scrollTo(selection) }
            }
        }
    }

    private func header(_ title: String, count: Int) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.headline)
            if count > 0 {
                Text("\(count)")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
                    .accessibilityLabel("\(count) comments")
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    /// A batch's header: when it was sent, how far it is, and whether it
    /// still waits for an agent.
    private func batchHeader(_ batch: Batch, _ comments: [Comment]) -> some View {
        let waits = model.listeners.outbox.pending.contains { $0.batchID == batch.id }
        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: waits ? "clock" : "paperplane.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            // Two digits for the hour: "Sent at 00:13" can't be read as a
            // time in the video.
            Text("Sent at \(batch.sentAt.formatted(.dateTime.hour(.twoDigits(amPM: .abbreviated)).minute(.twoDigits)))")
                .font(.subheadline.weight(.semibold))
            Spacer(minLength: 8)
            Text(waits ? "\(Self.progress(of: comments)) · waiting for an agent" : Self.progress(of: comments))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 2)
        .accessibilityElement(children: .combine)
    }

    /// What the agent said about the batch as one, under its header.
    private func batchMessages(_ batch: Batch) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("About the whole batch")
                .font(.caption2.weight(.semibold))
                .textCase(.uppercase)
                .kerning(0.4)
                .foregroundStyle(.secondary)
            ThreadView(messages: batch.messages, agent: model.agentName)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.agent.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.agent.opacity(0.22), lineWidth: 1) }
        .padding(.horizontal, 12)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("The agent's messages about the whole batch")
    }

    private var nothingQueued: some View {
        Text("Nothing queued. Press C to comment on the moment you're watching.")
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.bottom, 2)
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
