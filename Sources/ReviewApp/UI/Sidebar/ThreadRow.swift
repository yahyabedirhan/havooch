import ReviewCore
import ReviewWire
import SwiftUI

/// The words of a collapsed thread (D 3.3): its name, its frame's time,
/// its state and the start of its last message.
struct ThreadSummary: Equatable {
    /// `#3`, or `General`.
    var title: String
    /// The frame's time as the player bar shows it (`0:12`); nil for General.
    var time: String?
    var state: MessageState?
    /// Who wrote the last message and its words, on one line:
    /// `Claude Code: Slowed the intro down`. General with no message says
    /// what it is for.
    var preview: String
    /// Whether the agent waits for the person's answer on the thread.
    var waitsForAnswer: Bool

    init(_ thread: ReviewThread, agent: String) {
        title = thread.isGeneral ? "General" : "#\(thread.number)"
        time = thread.time.map { TimeCode.text($0.rounded(.down)) }
        state = thread.state
        waitsForAnswer = thread.openQuestion != nil
        if let last = thread.messages.last {
            let who = last.author == .agent ? agent : "You"
            let words = last.text.split(whereSeparator: \.isNewline).joined(separator: " ")
            preview = "\(who): \(words)"
        } else {
            preview = thread.isGeneral ? "Talk with the agent about the whole video" : "No messages"
        }
    }

    /// The row as one line, for VoiceOver.
    var text: String {
        let state = waitsForAnswer ? "waiting for your answer" : self.state.map(StateLook.name)
        return [title, time, state, preview].compactMap(\.self).joined(separator: ", ")
    }
}

/// One collapsed thread in the sidebar (D 3.3): its number, its keyframe
/// thumbnail, its state and the start of its last message. A click expands
/// it. General has a symbol in the keyframe's place.
struct ThreadRow: View {
    let model: AppModel
    let thread: ReviewThread

    @State private var isHovered = false
    @Environment(\.palette) private var palette

    static let thumbnail = CGSize(width: 64, height: 36)

    var body: some View {
        let summary = ThreadSummary(thread, agent: model.agentName)
        HStack(alignment: .center, spacing: 10) {
            picture
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(summary.title)
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                    if let time = summary.time {
                        Text(time)
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(palette[.textSecondary])
                    }
                    Spacer(minLength: 4)
                    if summary.waitsForAnswer {
                        Label("Answer", systemImage: "questionmark.circle.fill")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(palette[.question])
                            .labelStyle(.titleAndIcon)
                            .fixedSize()
                    } else if let state = summary.state {
                        StateChip(state: state)
                    }
                }
                Text(summary.preview)
                    .font(.callout)
                    .foregroundStyle(palette[.textSecondary])
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .padding(.horizontal, Metrics.sidebarPadding)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isHovered ? palette[.sidebarRowHover] : Color.clear)
        .animation(.smooth(duration: 0.12), value: isHovered)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture { model.expandThread(thread.id) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary.text)
        .accessibilityHint("Shows the conversation")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { model.expandThread(thread.id) }
    }

    @ViewBuilder
    private var picture: some View {
        if thread.isGeneral {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(palette[.textSecondary])
                .frame(width: Self.thumbnail.width, height: Self.thumbnail.height)
                .background(palette[.sidebarSection], in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .accessibilityHidden(true)
        } else {
            SidebarPicture(file: model.keyframe(of: thread), side: Self.thumbnail.width, fills: true)
                .frame(width: Self.thumbnail.width, height: Self.thumbnail.height)
        }
    }
}
