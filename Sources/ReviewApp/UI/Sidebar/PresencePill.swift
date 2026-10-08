import ReviewCore
import SwiftUI

/// The words of the footer's presence pill: one word
/// on the pill, and on hover who the agent is and what happens to a send
/// made now. A click on the pill opens the Connect view (G1).
struct PresencePill: Equatable {
    /// "Listening", "Working", "Reconnecting" or "No agent".
    var title: String
    /// The hover line, which names the agent: "Claude Code is listening".
    var help: String
    /// The agent whose logo the pill shows in place of its glyph: the
    /// listener's harness while it listens, works or reconnects. Nil with
    /// no listener, or for a name no known agent has: the pill shows its glyph.
    var logo: KnownAgent?
    /// Whether the agent the last run had is reconnecting after a relaunch
    /// (G6): the pill takes the working colour and its logo turns grey.
    var isReconnecting = false

    init(presence: Presence, session: String?, pendingSends: Int) {
        logo = presence == .absent ? nil : session.flatMap(KnownAgent.init(sender:))
        let agent = session ?? "An agent"
        let waiting = Self.waiting(pendingSends)
        switch presence {
        case .listening:
            title = "Listening"
            help = "\(agent) is listening. It gets what you send at once."
        case .working:
            title = "Working"
            help = "\(agent) is working on a send. What you send now waits for its next `havooch wait`." + waiting
        case .absent:
            title = "No agent"
            help = "No agent is listening. What you send waits for the next one. Click to connect an agent." + waiting
        }
    }

    /// The pill while `agent`, the last run's listener, reconnects.
    static func reconnecting(_ agent: String, pendingSends: Int) -> PresencePill {
        var pill = PresencePill(presence: .absent, session: agent, pendingSends: pendingSends)
        pill.title = "Reconnecting"
        pill.help = "Havooch relaunched. \(agent) picks up again on its next `havooch wait`." + waiting(pendingSends)
        pill.logo = KnownAgent(sender: agent)
        pill.isReconnecting = true
        return pill
    }

    /// The pill for `phase`, with `pendingSends` in line.
    static func of(_ phase: ListenerQueue.Phase, presence: Presence, pendingSends: Int) -> PresencePill {
        switch phase {
        case .reconnecting(let session, _): reconnecting(session.name, pendingSends: pendingSends)
        case .connected(let session): PresencePill(presence: presence, session: session.name, pendingSends: pendingSends)
        case .none: PresencePill(presence: .absent, session: nil, pendingSends: pendingSends)
        }
    }

    private static func waiting(_ pendingSends: Int) -> String {
        pendingSends > 0 ? " \(pendingSends) \(pendingSends == 1 ? "send waits" : "sends wait") for it." : ""
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

/// The presence chip: the agent's harness logo, or a glyph, and a word in a
/// soft capsule of the presence's colour, with a chevron that turns while
/// the Connect view shows. The glyph pulses while the agent works, unless
/// motion is reduced; the word says it beside a logo. Hover names the agent.
struct PresenceChip: View {
    let presence: Presence
    let pill: PresencePill
    /// Whether the Connect view shows: the chevron points down.
    var isOpen = false

    @State private var hover = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.palette) private var palette

    var body: some View {
        let colour = pill.isReconnecting ? palette[.stateWorking] : palette.presence(presence)
        HStack(spacing: 5) {
            Group {
                if let agent = pill.logo {
                    AgentMark(agent: agent, size: 14)
                        .saturation(pill.isReconnecting ? 0 : 1)
                        .opacity(pill.isReconnecting ? 0.6 : 1)
                } else {
                    Image(systemName: PresencePill.glyph(presence))
                        .symbolRenderingMode(.hierarchical)
                        .symbolEffect(.variableColor.iterative, options: .repeating, isActive: presence == .working && !reduceMotion)
                }
            }
            Text(pill.title)
            Image(systemName: "chevron.up")
                .font(.system(size: 8, weight: .bold))
                .rotationEffect(.degrees(isOpen ? 180 : 0))
                .opacity(hover || isOpen ? 0.9 : 0.55)
        }
        .font(.callout.weight(.medium))
        .lineLimit(1)
        .fixedSize()
        .foregroundStyle(colour)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(colour.opacity(hover || isOpen ? 0.24 : 0.14), in: Capsule())
        .contentShape(Capsule())
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.15), value: hover)
        .help(pill.help)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Listener: \(pill.title)")
        .accessibilityHint(pill.help)
    }
}
