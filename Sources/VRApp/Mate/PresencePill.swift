import SwiftUI
import VRReview

/// The words and colour of the presence indicator, one per presence.
struct PresenceStyle: Equatable {
    var label: String
    var color: Color

    static func of(_ presence: Presence) -> PresenceStyle {
        switch presence {
        case .listening: PresenceStyle(label: "Listening", color: Theme.sage)
        case .working: PresenceStyle(label: "Working", color: Theme.apricot)
        case .absent: PresenceStyle(label: "No listener", color: .secondary)
        }
    }
}

/// Whether a listener is there, always in sight at the foot of the
/// sidebar, as a quiet dot and a word: sage Listening, apricot Working,
/// grey No listener. Hovering names the listener and its folder.
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
                .frame(width: 7, height: 7)
            Text(style.label)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
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
