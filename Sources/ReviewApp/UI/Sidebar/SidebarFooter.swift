import ReviewCore
import SwiftUI

/// The foot of the sidebar, proto-3's line: whether an agent listens, how
/// many messages are queued, and Send. Sending is safe either way: with no
/// agent the send waits for the next one.
///
/// As tall as the player bar under the stage, on the same background, so
/// the two meet on one line across the window (D 4.9).
struct SidebarFooter: View {
    let model: AppModel
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 8) {
            // Each second: an agent that stops answering turns absent with no event.
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let outbox = model.listeners.outbox
                let presence = outbox.presence(at: context.date)
                PresenceChip(
                    presence: presence,
                    pill: PresencePill(presence: presence, session: outbox.session?.name, pendingSends: outbox.pending.count)
                )
            }
            Spacer(minLength: 8)
            Text("\(model.queuedCount) queued")
                .font(.callout.monospacedDigit())
                .foregroundStyle(palette[.textSecondary])
                .lineLimit(1)
                .fixedSize()
            Button("Send") { model.send() }
                .buttonStyle(.borderedProminent)
                .fixedSize()
                .disabled(!model.canSend)
                .help(model.canSend ? "Send the queue to your agent at once (⌘↩)" : "Nothing is queued")
        }
        .padding(.horizontal, Metrics.railPadding)
        .frame(maxWidth: .infinity)
        .frame(height: Metrics.barHeight)
        .background(palette[.bar])
    }
}
