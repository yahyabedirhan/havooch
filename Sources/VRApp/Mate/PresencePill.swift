import SwiftUI
import VRReview

/// The words and colour of the presence pill, one per presence.
struct PresenceStyle: Equatable {
    var label: String
    var color: Color

    static func of(_ presence: Presence) -> PresenceStyle {
        switch presence {
        case .listening: PresenceStyle(label: "Listening", color: .green)
        case .working: PresenceStyle(label: "Working", color: .orange)
        case .absent: PresenceStyle(label: "No listener", color: .gray)
        }
    }
}

/// Whether a listener is there, always in sight in the toolbar: green
/// Listening, orange Working, grey No listener. Hovering names the
/// listener and its folder.
struct PresencePill: View {
    let listener: ListenerQueue

    var body: some View {
        // The clock ticks only while time alone can change the presence.
        if listener.presenceRunsOut {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                pill(listener.presence(at: context.date))
            }
        } else {
            pill(listener.presence)
        }
    }

    private func pill(_ presence: Presence) -> some View {
        let style = PresenceStyle.of(presence)
        return HStack(spacing: 6) {
            Circle()
                .fill(style.color)
                .frame(width: 8, height: 8)
            Text(style.label)
                .font(.callout.weight(.medium))
                .foregroundStyle(presence == .absent ? .secondary : .primary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(style.color.opacity(0.16), in: Capsule())
        .help(hint(presence))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Listener: \(style.label)")
    }

    /// Who listens and where, or how a listener comes to be.
    private func hint(_ presence: Presence) -> String {
        guard presence != .absent, let session = listener.session else {
            return "No agent is listening. A batch you send waits for the next `video-review wait`."
        }
        return "\(session.name) in \(session.place)"
    }
}
