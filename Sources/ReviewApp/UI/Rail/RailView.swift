import ReviewCore
import SwiftUI

/// The rail beside the stage: the queue on top, then each batch, newest
/// first, with the agent's messages about it and its comments as rows in
/// time order, then the send bar.
///
/// Nothing in the rail is a bordered card. Each section starts with a
/// header band, rows are split by hairlines, and the selected row is told by
/// its fill; only thread messages sit in bubbles, as in a chat.
struct RailView: View {
    let model: AppModel

    /// One section of rows: the queue, or a batch.
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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let groups = Self.groups(comments: model.comments, batches: model.batches)
        VStack(spacing: 0) {
            if model.comments.isEmpty {
                sectionHeader { queueTitle(count: 0) }
                empty
            } else {
                list(groups)
            }
            SendBar(model: model)
        }
    }

    private func list(_ groups: [CardGroup]) -> some View {
        ScrollViewReader { scroll in
            ScrollView {
                // Not lazy: a row that moves from the queue to its batch
                // must be drawn again in its new state, and a review has
                // tens of comments, not thousands. Pinned section headers
                // need a lazy stack, so the headers scroll with their rows.
                VStack(spacing: 0) {
                    ForEach(groups) { group in
                        section(group)
                    }
                }
                .padding(.bottom, 12)
            }
            .onChange(of: model.selection) { _, selection in
                guard let selection else { return }
                if reduceMotion {
                    scroll.scrollTo(selection)
                } else {
                    withAnimation(.smooth(duration: 0.35)) { scroll.scrollTo(selection) }
                }
            }
        }
    }

    /// One section: its header band, the batch's own messages, then its
    /// rows with a hairline between each two.
    private func section(_ group: CardGroup) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let batch = group.batch {
                sectionHeader { batchTitle(batch, group.cards.map(\.comment)) }
                if !batch.messages.isEmpty { batchMessages(batch) }
            } else {
                sectionHeader { queueTitle(count: group.cards.count) }
                if group.cards.isEmpty { nothingQueued }
            }
            ForEach(group.cards) { card in
                CommentRow(model: model, comment: card.comment, number: card.number)
                    .id(card.id)
                if card.id != group.cards.last?.id {
                    Divider()
                        .padding(.leading, CommentRow.textInset)
                }
            }
        }
    }

    /// A section's header: a full-width band behind the title, as a list's
    /// section header, with no border.
    private func sectionHeader<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            content()
        }
        .padding(.horizontal, Theme.railPadding)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.sectionBand(contrast))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private func queueTitle(count: Int) -> some View {
        Text("Queue")
            .font(.subheadline.weight(.semibold))
        Spacer(minLength: 8)
        if count > 0 {
            Text("\(count) comment\(count == 1 ? "" : "s")")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    /// A batch's title: when it was sent, how far it is, and whether it
    /// still waits for an agent.
    @ViewBuilder
    private func batchTitle(_ batch: Batch, _ comments: [Comment]) -> some View {
        let waits = model.listeners.outbox.pending.contains { $0.batchID == batch.id }
        Image(systemName: waits ? "clock" : "paperplane")
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
        // Two digits for the hour: "Sent at 00:13" can't be read as a
        // time in the video.
        Text("Sent at \(batch.sentAt.formatted(.dateTime.hour(.twoDigits(amPM: .abbreviated)).minute(.twoDigits)))")
            .font(.subheadline.weight(.semibold))
        Spacer(minLength: 8)
        Text(waits ? "\(Self.progress(of: comments)) · waiting for an agent" : Self.progress(of: comments))
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }

    /// What the agent said about the batch as one, under its header, as
    /// chat bubbles.
    private func batchMessages(_ batch: Batch) -> some View {
        ThreadView(messages: batch.messages, agent: model.agentName)
            .padding(.horizontal, Theme.railPadding)
            .padding(.vertical, 12)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("The agent's messages about the whole batch")
    }

    private var nothingQueued: some View {
        Text("Nothing queued. Press C to comment on the moment you're watching.")
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.railPadding)
            .padding(.vertical, 12)
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
