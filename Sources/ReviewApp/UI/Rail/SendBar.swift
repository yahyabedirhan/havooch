import ReviewCore
import SwiftUI

/// The words of the presence pill: whether an agent is there for a send,
/// and what happens to one sent now.
struct PresencePill: Equatable {
    /// "Agent listening", "Agent working" or "No agent listening".
    var title: String
    /// Who listens, and how many sends wait for a listener; with no
    /// agent and nothing waiting, that a send made now waits.
    var detail: String

    init(presence: Presence, session: String?, pendingSends: Int) {
        let waiting = pendingSends > 0 ? "\(pendingSends) \(pendingSends == 1 ? "send" : "sends") waiting" : nil
        switch presence {
        case .listening:
            title = "Agent listening"
            detail = [session, waiting].compactMap(\.self).joined(separator: " · ")
        case .working:
            title = "Agent working"
            detail = [session, waiting].compactMap(\.self).joined(separator: " · ")
        case .absent:
            title = "No agent listening"
            detail = waiting ?? "a send will wait"
        }
    }

    /// The pill as one line, for VoiceOver and the tooltip.
    var text: String { detail.isEmpty ? title : "\(title) · \(detail)" }
}

/// The foot of the rail: whether an agent listens, and the Send button with
/// how many messages it sends. Sending is safe either way: with no agent
/// the send waits for the next one.
///
/// It is as tall as the timeline lane under the stage, so the line over it
/// carries on the stage's lower edge across the window.
struct SendBar: View {
    let model: AppModel
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(spacing: 10) {
            // Each second: an agent that stops answering turns absent with no event.
            TimelineView(.periodic(from: .now, by: 1)) { context in
                presence(at: context.date)
            }
            sendButton
        }
        .padding(.horizontal, Metrics.railPadding)
        .frame(maxWidth: .infinity)
        .frame(height: Metrics.footerHeight)
        .background(palette[.bar])
    }

    /// Whether an agent is there, as a quiet dot and words: no capsule.
    private func presence(at time: Date) -> some View {
        let outbox = model.listeners.outbox
        let presence = outbox.presence(at: time)
        let pill = PresencePill(presence: presence, session: outbox.session?.name, pendingSends: outbox.pending.count)
        return HStack(spacing: 6) {
            PresenceDot(presence: presence)
            Text(pill.title)
                .font(.callout.weight(.medium))
                .foregroundStyle(presence == .absent ? palette[.textSecondary] : palette[.textPrimary])
                .lineLimit(1)
                .fixedSize()
            if !pill.detail.isEmpty {
                Text("· \(pill.detail)")
                    .font(.callout)
                    .foregroundStyle(palette[.textSecondary])
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 0)
        }
        .help(Self.help(presence))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(pill.text)
    }

    private var sendButton: some View {
        let count = model.sendCount
        return Button {
            model.send()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "paperplane.fill")
                    .imageScale(.small)
                Text(count == 0 ? "Send" : "Send \(count) message\(count == 1 ? "" : "s")")
                    .fontWeight(.semibold)
                Text("⌘↩")
                    .opacity(0.7)
            }
            .frame(maxWidth: .infinity)
            .foregroundStyle(palette[.textOnAccent])
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(count == 0)
        .help(count == 0 ? "Nothing is queued" : "Send the queue to your agent at once (Cmd+Return)")
        .accessibilityLabel(count == 0 ? "Send" : "Send \(count) message\(count == 1 ? "" : "s")")
    }

    private static func help(_ presence: Presence) -> String {
        switch presence {
        case .listening: "An agent runs `video-review wait`: it gets your messages the moment you send them"
        case .working: "The agent took a send and works on it. What you send now waits for its next `video-review wait`"
        case .absent: "No agent runs `video-review wait`. What you send waits for the next one"
        }
    }
}

/// The presence dot, told by shape as well as colour: filled for an agent
/// that listens, half for one that works, hollow for none.
private struct PresenceDot: View {
    let presence: Presence
    @Environment(\.palette) private var palette

    var body: some View {
        Group {
            switch presence {
            case .listening: Image(systemName: "circle.fill")
            case .working: Image(systemName: "circle.lefthalf.filled")
            case .absent: Image(systemName: "circle")
            }
        }
        .font(.system(size: 8, weight: .bold))
        .foregroundStyle(palette.presence(presence))
        .accessibilityHidden(true)
    }
}
