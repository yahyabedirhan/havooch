import SwiftUI
import VRReview

/// The bar under the comments: whether a listener is there, how many
/// comments are queued, and the button that sends them. Sending with no
/// listener is allowed; a line above the bar then says the batch waits. The
/// bar itself is the transport bar's height, so the two line up along the
/// window's bottom; the line goes above it, never into it.
struct SendBar: View {
    let model: ReviewModel

    var body: some View {
        // Presence also ends by itself, a while after a delivered batch.
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let presence = model.presence
            let queued = model.session?.queue.count ?? 0
            let waiting = model.outbox.parcels.filter { $0.delivery == .pending }.count
            VStack(spacing: 0) {
                if let note = Self.note(failure: model.sendFailure, presence: presence, queued: queued, waiting: waiting) {
                    Divider()
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(model.sendFailure == nil ? Color.secondary : Color.red)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, Theme.edge)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Divider()
                HStack(spacing: 8) {
                    PresenceChip(presence: presence, name: model.outbox.listener?.name)
                    Spacer()
                    Text("\(queued) queued")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Button("Send") { model.sendByPerson() }
                        .buttonStyle(.borderedProminent)
                        .disabled(queued == 0 && model.composing == nil)
                        .help("Send the queued comments as one batch (⌘↩)")
                }
                .padding(.horizontal, Theme.edge)
                .frame(height: Theme.footerHeight)
            }
            .background(.bar)
        }
    }

    /// The line under the bar: why the last send failed, else what happens
    /// to a batch while no listener is there.
    nonisolated static func note(failure: String?, presence: Outbox.Presence, queued: Int, waiting: Int) -> String? {
        if let failure { return failure }
        guard presence == .absent else { return nil }
        if waiting > 0 {
            return "\(waiting) batch\(waiting == 1 ? " waits" : "es wait") for the next listener."
        }
        return queued > 0 ? "No agent is listening. A batch you send waits for the next listener." : nil
    }
}

/// Whether an agent is listening, as a word with a glyph and a colour.
struct PresenceChip: View {
    let presence: Outbox.Presence
    /// The listener session's name, for the tooltip.
    let name: String?

    var body: some View {
        Label(Theme.label(for: presence), systemImage: Theme.glyph(for: presence))
            .font(.callout.weight(.medium))
            .foregroundStyle(Theme.colour(for: presence))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Theme.colour(for: presence).opacity(0.14), in: Capsule())
            .help(presence == .absent ? "No agent runs `video-review wait`" : "\(name ?? "An agent") is \(presence.rawValue)")
            .accessibilityLabel("Listener: \(Theme.label(for: presence))")
    }
}
