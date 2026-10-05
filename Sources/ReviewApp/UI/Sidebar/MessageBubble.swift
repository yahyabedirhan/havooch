import ReviewCore
import SwiftUI

/// The words of one message's heading: who said it, and how.
struct ThreadHeading: Equatable {
    /// "Claude Code asked", "You answered", "Claude Code".
    var title: String
    /// The symbol in the message's avatar, when it shows no agent logo.
    var symbol: String

    init(_ message: Message, agent: String) {
        switch (message.author, message.kind) {
        case (.agent, .question): (title, symbol) = ("\(agent) asked", "questionmark")
        case (.agent, _): (title, symbol) = (agent, "sparkles")
        case (.person, .answer): (title, symbol) = ("You answered", "person.fill")
        case (.person, _): (title, symbol) = ("You", "person.fill")
        }
    }
}

/// One message of a thread (D 3.4): an avatar for its
/// author, who said it and when, and the words in a soft bubble. A region
/// message shows its crop under its words, at its place in the
/// conversation (D 3.5). A person's message shows its state; a queued one
/// can be edited and deleted (D 1.5). An open question is picked out: the
/// agent waits for it.
struct MessageBubble: View {
    let model: AppModel
    let message: Message
    var isOpenQuestion = false

    /// The text being edited; nil while the message only shows.
    @State private var edited: String?
    @Environment(\.palette) private var palette

    private static let avatar: CGFloat = 20
    /// The largest a crop shows in the conversation.
    private static let cropSize = CGSize(width: 220, height: 140)

    var body: some View {
        let heading = ThreadHeading(message, agent: model.agentName)
        HStack(alignment: .top, spacing: 8) {
            // The agent's harness logo when its session names a known
            // agent; else the symbol in the author's disc.
            AgentAvatar(
                agent: message.author == .agent ? model.agent : nil,
                size: Self.avatar, symbol: heading.symbol, fill: avatarFill
            )
            VStack(alignment: .leading, spacing: 4) {
                header(heading)
                if let edited {
                    editor(edited)
                } else {
                    Text(message.text)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(bubble, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        // The bubble hugs its words, as in a chat.
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if let file = model.crop(of: message) {
                    crop(file)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(heading.title): \(message.text)")
    }

    private func header(_ heading: ThreadHeading) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(heading.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isQuestion ? palette[.question] : palette[.textSecondary])
                .lineLimit(1)
            if isOpenQuestion {
                Text("waiting for you")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(palette[.question])
            }
            if message.isWork, let state = message.state {
                StateChip(state: state)
            }
            Spacer(minLength: 4)
            if message.isWork, message.state?.isEditable == true, edited == nil {
                RowButton("Edit", symbol: "pencil") { edited = message.text }
                RowButton("Delete", symbol: "trash") { model.delete(message.id) }
            }
            Text(message.at.formatted(.dateTime.hour(.twoDigits(amPM: .abbreviated)).minute(.twoDigits)))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(palette[.textTertiary])
                .fixedSize()
        }
    }

    /// The crop of a region message, as an attachment under its words.
    private func crop(_ file: URL) -> some View {
        SidebarPicture(file: file, side: Self.cropSize.width, shape: 16 / 9)
            .frame(maxWidth: Self.cropSize.width, maxHeight: Self.cropSize.height, alignment: .leading)
            .help("The region this message points at")
    }

    private func editor(_ text: String) -> some View {
        VStack(alignment: .trailing, spacing: 6) {
            MessageField(text: binding(text), placeholder: "Message", commit: save, cancel: { edited = nil })
                .frame(height: 60)
            HStack(spacing: 8) {
                Button("Cancel") { edited = nil }
                Button("Save", action: save)
                    .buttonStyle(.borderedProminent)
                    .disabled(!AppModel.hasWords(text))
            }
            .controlSize(.small)
        }
    }

    private func binding(_ text: String) -> Binding<String> {
        Binding(get: { edited ?? text }, set: { edited = $0 })
    }

    private func save() {
        guard let edited, AppModel.hasWords(edited) else { return }
        model.edit(message.id, text: edited)
        self.edited = nil
    }

    private var isQuestion: Bool { message.author == .agent && message.kind == .question }

    /// The avatar's fill: the agent's colour, a question's, or the person's.
    private var avatarFill: Color {
        switch (message.author, message.kind) {
        case (.agent, .question): palette[.question]
        case (.agent, _): palette[.agent]
        case (.person, _): palette[.person]
        }
    }

    /// The bubble behind the words: no stroke, only a light fill.
    private var bubble: Color {
        switch (message.author, message.kind) {
        case (.agent, .question): palette[.bubbleQuestion]
        case (.agent, _): palette[.bubbleAgent]
        case (.person, _): palette[.bubblePerson]
        }
    }
}

/// A message's state: its glyph and its name, in its colour, so a state is
/// never told by colour alone.
struct StateChip: View {
    let state: MessageState
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: StateLook.glyph(state))
                .imageScale(.small)
            Text(StateLook.name(state))
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(palette.state(state))
        .lineLimit(1)
        .fixedSize()
        .accessibilityElement(children: .combine)
    }
}

/// A quiet symbol button in the sidebar.
struct RowButton: View {
    let title: String
    let symbol: String
    let action: () -> Void

    init(_ title: String, symbol: String, action: @escaping () -> Void) {
        self.title = title
        self.symbol = symbol
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .medium))
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(QuietButtonStyle())
        .help(title)
        .accessibilityLabel(title)
    }
}
