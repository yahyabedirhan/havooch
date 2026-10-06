import ReviewCore
import SwiftUI

/// The foot of the sidebar, one line: whether an agent listens and what it
/// does now (its newest activity), how many messages are queued, and Send.
/// Sending is safe either way: with no agent the send waits for the next
/// one.
///
/// As tall as the player bar under the stage, on the window's one
/// surface, so the two meet on one line across the window (D 4.9). A
/// hairline above it separates it from the threads; it lies inside that
/// height.
struct SidebarFooter: View {
    let model: AppModel
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 8) {
            // Each second: an agent that stops answering turns absent with no event.
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let outbox = model.listeners.outbox
                let presence = outbox.presence(at: context.date)
                HStack(spacing: 8) {
                    PresenceChip(
                        presence: presence,
                        pill: PresencePill(presence: presence, session: outbox.session?.name, pendingSends: outbox.pending.count)
                    )
                    // The newest activity of any thread, with no glyph: the chip pulses beside it.
                    if let activity = model.listeners.activities(at: context.date).first {
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
            Spacer(minLength: 8)
            Text("\(model.queuedCount) queued")
                .font(.callout.monospacedDigit())
                .foregroundStyle(palette[.textSecondary])
                .lineLimit(1)
                .fixedSize()
            Button("Send") { model.send() }
                .buttonStyle(.borderedProminent)
                .pressedByKeys(in: model) { model.send() }
                .fixedSize()
                .disabled(!model.canSend)
                .help(model.canSend ? "Send the queue to your agent at once (⌘↩)" : "Nothing is queued")
        }
        .padding(.horizontal, Metrics.sidebarPadding)
        .frame(maxWidth: .infinity)
        .frame(height: Metrics.barHeight)
        .background(palette[.window])
        .overlay(alignment: .top) { Hairline(axis: .horizontal) }
    }
}
