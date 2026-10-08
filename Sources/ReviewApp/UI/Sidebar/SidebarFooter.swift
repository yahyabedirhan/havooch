import ReviewCore
import SwiftUI

/// The foot of the sidebar, one line: whether an agent listens and what it
/// does now (its newest activity), how many messages are queued, and Send.
/// Sending is safe either way: with no agent the send waits for the next
/// one, and the Connect view opens to say so (G8). A click on the presence
/// pill opens the Connect view, and goes back when it shows (G1).
///
/// As tall as the player bar under the stage, on the window's one
/// surface, so the two meet on one line across the window (D 4.9). A
/// hairline above it separates it from the threads; it lies inside that
/// height.
struct SidebarFooter: View {
    let model: WindowModel
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 8) {
            // Each second: an agent that stops answering turns absent with no event.
            TimelineView(.periodic(from: .now, by: 1)) { context in
                // The window's own listener; a window with no video has none.
                let outbox = model.listener?.outbox ?? Outbox()
                let presence = outbox.presence(at: context.date)
                let pill = PresencePill.of(model.listenerPhase(at: context.date), presence: presence, pendingSends: outbox.pending.count)
                HStack(spacing: 8) {
                    Button {
                        model.toggleConnect(.pill)
                    } label: {
                        PresenceChip(presence: presence, pill: pill, isOpen: model.connect != nil)
                    }
                    .buttonStyle(.plain)
                    .pressedByKeys(in: model) { model.toggleConnect(.pill) }
                    // The newest activity of any thread, with no glyph: the chip pulses beside it.
                    if let activity = model.listener?.activities(at: context.date).first {
                        Text(activity.text)
                            .font(.callout)
                            .foregroundStyle(palette[.textSecondary])
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .help(activity.text)
                            .accessibilityLabel(ActivityLine.voice(agent: model.agentName, text: activity.text))
                    }
                }
            }
            // The pill and the activity take all the width the count and Send
            // leave, so the activity truncates only when there is no room.
            .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(model.queuedCount) queued")
                .font(.callout.monospacedDigit())
                .foregroundStyle(palette[.textSecondary])
                .lineLimit(1)
                .fixedSize()
            Button("Send") { model.send() }
                .filledButton(palette)
                .pressedByKeys(in: model) { model.send() }
                .fixedSize()
                .disabled(!model.canSend)
                .coachRing(model.tourRings(.send), radius: 6)
                .help(model.canSend ? "Send the queue to your agent at once (⌘↩)" : "Nothing is queued")
        }
        .padding(.horizontal, Metrics.sidebarPadding)
        .frame(maxWidth: .infinity)
        .frame(height: Metrics.barHeight)
        .background(palette[.window])
        .overlay(alignment: .top) { Hairline(axis: .horizontal) }
    }
}
