import ReviewCore
import SwiftUI

/// The words of the footer's presence pill, as proto-3 says them: one word
/// on the pill, and on hover who the agent is and what happens to a send
/// made now.
struct PresencePill: Equatable {
    /// "Listening", "Working" or "No listener".
    var title: String
    /// The hover line, which names the agent: "Claude Code is listening".
    var help: String

    init(presence: Presence, session: String?, pendingSends: Int) {
        let agent = session ?? "An agent"
        let waiting = pendingSends > 0 ? " \(pendingSends) \(pendingSends == 1 ? "send waits" : "sends wait") for it." : ""
        switch presence {
        case .listening:
            title = "Listening"
            help = "\(agent) is listening. It gets what you send at once."
        case .working:
            title = "Working"
            help = "\(agent) is working on a send. What you send now waits for its next `video-review wait`." + waiting
        case .absent:
            title = "No listener"
            help = "No agent runs `video-review wait`. What you send waits for the next one." + waiting
        }
    }

    /// The pill's glyph, an SF Symbol: the shape says the presence
    /// as well as the colour.
    static func glyph(_ presence: Presence) -> String {
        switch presence {
        case .listening: "antenna.radiowaves.left.and.right"
        case .working: "ellipsis.circle.fill"
        case .absent: "antenna.radiowaves.left.and.right.slash"
        }
    }
}

/// proto-3's presence chip: a glyph and a word in a soft capsule of the
/// presence's colour. The glyph pulses while the agent works, unless motion
/// is reduced. Hover names the agent.
struct PresenceChip: View {
    let presence: Presence
    let pill: PresencePill

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.palette) private var palette

    var body: some View {
        let colour = palette.presence(presence)
        Label(pill.title, systemImage: PresencePill.glyph(presence))
            .font(.callout.weight(.medium))
            .lineLimit(1)
            .fixedSize()
            .symbolRenderingMode(.hierarchical)
            .symbolEffect(.variableColor.iterative, options: .repeating, isActive: presence == .working && !reduceMotion)
            .foregroundStyle(colour)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(colour.opacity(0.14), in: Capsule())
            .contentShape(Capsule())
            .help(pill.help)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Listener: \(pill.title)")
            .accessibilityHint(pill.help)
    }
}
