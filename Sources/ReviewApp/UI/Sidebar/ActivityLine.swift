import ReviewCore
import SwiftUI

struct ThreadActivity: View {
    let model: WindowModel
    let thread: ThreadID

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            if let activity = model.listener?.activity(on: thread, at: context.date) {
                ActivityLine(text: activity.text, agent: model.agentName)
                    .padding(.leading, MessageBubble.avatar + 8)
                    .padding(.trailing, MessageBubble.agentInset)
                    .padding(.top, MessageBubble.gap)
                    .transition(.opacity)
            }
        }
    }
}

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

    static func voice(agent: String, text: String) -> String {
        "\(agent) now: \(text)"
    }
}
