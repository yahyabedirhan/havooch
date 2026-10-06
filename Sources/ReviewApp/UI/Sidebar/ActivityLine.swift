import ReviewCore
import SwiftUI

/// The activity, what the agent does now (`status working` with a text):
/// a quiet line with the working glyph, under the last message of the
/// thread view's conversation, where the agent's next message will come.
/// It shows while an agent is there and the line's message works; `done`
/// or `failed` clears it.
struct ThreadActivity: View {
    let model: AppModel
    let thread: ThreadID

    var body: some View {
        // Each second: an agent that stops answering takes its line with it.
        TimelineView(.periodic(from: .now, by: 1)) { context in
            if let activity = model.listeners.activity(on: thread, at: context.date) {
                ActivityLine(text: activity.text, agent: model.agentName)
                    // Under the agent's bubbles, past the avatar's column.
                    .padding(.leading, MessageBubble.avatar + 8)
                    .padding(.trailing, MessageBubble.agentInset)
                    .padding(.top, MessageBubble.gap)
                    .transition(.opacity)
            }
        }
    }
}

/// The live line itself: the working glyph, pulsing unless motion is
/// reduced, and the agent's words in the secondary colour.
struct ActivityLine: View {
    let text: String
    let agent: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: StateLook.glyph(.working))
                .font(.caption.weight(.semibold))
                .foregroundStyle(palette.state(.working))
                .symbolEffect(.variableColor.iterative, options: .repeating, isActive: !reduceMotion)
                .accessibilityHidden(true)
            Text(text)
                .font(.callout)
                .foregroundStyle(palette[.textSecondary])
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Self.voice(agent: agent, text: text))
    }

    /// What VoiceOver reads for an activity: `Claude Code now: Rendering`.
    static func voice(agent: String, text: String) -> String {
        "\(agent) now: \(text)"
    }
}
