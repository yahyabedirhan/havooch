import AppKit
import ReviewCore
import SwiftUI

/// Who wrote a message, as the conversation shows it (L40): "You", or the
/// agent's name with its harness for the logo. An agent's message keeps the
/// name of the listener session that wrote it; one kept before names were
/// takes `listener`, the name of the session listening now.
struct MessageWriter: Equatable {
    var name: String
    var agent: KnownAgent?

    init(_ message: Message, listener: String) {
        switch message.author {
        case .person: (name, agent) = ("You", nil)
        case .agent:
            name = message.sessionName ?? listener
            agent = KnownAgent(sender: name)
        }
    }
}

/// Where a message sits in a run of the agent's messages: the agent's name
/// shows once at the start of a run, its avatar once at the end, beside the
/// last bubble. A person's message is in no run.
struct ChatRun: Equatable {
    var startsRun = false
    var endsRun = false

    init(of index: Int, in messages: [Message]) {
        guard messages.indices.contains(index), messages[index].author == .agent else { return }
        startsRun = index == messages.startIndex || messages[index - 1].author != .agent
        endsRun = index == messages.index(before: messages.endIndex) || messages[index + 1].author != .agent
    }
}

/// What VoiceOver reads for a message: its writer, its kind and its state,
/// then its words. `You, message, Queued, on a region: Too fast`.
enum MessageVoice {
    static func text(_ message: Message, writer: String, isOpenQuestion: Bool) -> String {
        var parts = [writer]
        switch (message.author, message.kind) {
        case (.person, .answer): parts += ["answer", "sent at once"]
        case (.person, _):
            parts.append("message")
            if let state = message.state { parts.append(StateLook.name(state)) }
            if message.region != nil { parts.append("on a region") }
        case (.agent, .question): parts += ["question", isOpenQuestion ? "waiting for your answer" : "answered"]
        case (.agent, _): parts.append("reply")
        }
        return parts.joined(separator: ", ") + ": " + message.text
    }
}

/// What a message's menu (and VoiceOver's actions) offer: Edit and Delete
/// on a queued message only, since a sent one is a record; Copy on all.
enum MessageAction: CaseIterable, Identifiable {
    case edit, delete, copy

    var id: Self { self }

    var title: String {
        switch self {
        case .edit: "Edit"
        case .delete: "Delete"
        case .copy: "Copy"
        }
    }

    var symbol: String {
        switch self {
        case .edit: "pencil"
        case .delete: "trash"
        case .copy: "doc.on.doc"
        }
    }

    static func all(for message: Message) -> [MessageAction] {
        message.isWork && message.state?.isEditable == true ? [.edit, .delete, .copy] : [.copy]
    }
}

/// One message of a thread as a chat (L40, from variant 02 of the
/// prototype). The person's messages are trailing, in `bubblePerson` with a
/// tail, and a quiet line under the bubble holds the state, the region tag
/// and the time; a queued one has a dashed outline, Edit and Delete on
/// hover, and is edited in place; an answer is tinted with `question`. The
/// agent's messages are leading, in `bubbleAgent`, with its harness logo at
/// the end of a run and its name at the start; a question is a card in
/// `bubbleQuestion` headed "<agent> asks". A region message shows its crop
/// as an attachment under its bubble. A right-click offers Edit, Delete and
/// Copy where they apply.
struct MessageBubble: View {
    let model: AppModel
    let message: Message
    var isOpenQuestion = false
    var run: ChatRun

    /// The text being edited; nil while the message only shows.
    @State private var edited: String?
    @State private var isHovered = false
    /// Whether Edit or Delete has the keyboard focus: they show then as on
    /// hover, so Space never presses a button the person can't see.
    @State private var isEditFocused = false
    @State private var isDeleteFocused = false
    @Environment(\.palette) private var palette

    static let avatar: CGFloat = 24
    /// The room a person's message leaves at the leading side, and an
    /// agent's at the trailing side, so who wrote it reads from its place.
    static let personInset: CGFloat = 46
    static let agentInset: CGFloat = 34
    /// The space above a message: half of it inside a run of the agent's.
    /// A conversation adds it once more at its foot.
    static let gap: CGFloat = 8
    /// The bubble's corners, and the small one its tail is.
    static let corner: CGFloat = 16
    static let tail: CGFloat = 5
    /// The largest a crop shows in the conversation.
    private static let cropSize = CGSize(width: 220, height: 140)

    var body: some View {
        let writer = MessageWriter(message, listener: model.agentName)
        Group {
            if message.author == .person {
                person
            } else {
                agent(writer)
            }
        }
        .contextMenu {
            ForEach(MessageAction.all(for: message)) { action in
                Button(action.title, systemImage: action.symbol, role: action == .delete ? .destructive : nil) { perform(action) }
            }
        }
        .accessibilityElement(children: edited == nil ? .ignore : .contain)
        .accessibilityLabel(MessageVoice.text(message, writer: writer.name, isOpenQuestion: isOpenQuestion))
        .accessibilityActions {
            ForEach(MessageAction.all(for: message)) { action in
                Button(action.title) { perform(action) }
            }
        }
    }

    private func perform(_ action: MessageAction) {
        switch action {
        case .edit: edited = message.text
        case .delete: model.delete(message.id)
        case .copy:
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(message.text, forType: .string)
        }
    }

    // MARK: - The person's message

    private var isQueued: Bool { message.isWork && message.state?.isEditable == true }

    /// Edit and Delete show on hover, and while either has the keyboard focus.
    private var areActionsShown: Bool { isHovered || isEditFocused || isDeleteFocused }

    @ViewBuilder
    private var person: some View {
        if let edited {
            editor(edited)
                .padding(.top, Self.gap)
        } else {
            VStack(alignment: .trailing, spacing: 3) {
                HStack(alignment: .center, spacing: 4) {
                    if isQueued {
                        HStack(spacing: 1) {
                            RowButton("Edit", symbol: "pencil") { edited = message.text }
                                .pressedByKeys(in: model, isFocused: $isEditFocused) { edited = message.text }
                            RowButton("Delete", symbol: "trash") { model.delete(message.id) }
                                .pressedByKeys(in: model, isFocused: $isDeleteFocused) { model.delete(message.id) }
                        }
                        .opacity(areActionsShown ? 1 : 0)
                        .animation(.smooth(duration: 0.12), value: areActionsShown)
                    }
                    words
                        .background { personBubble }
                }
                if let file = model.crop(of: message) {
                    crop(file)
                }
                personLine
                    .padding(.trailing, 4)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.leading, Self.personInset)
            .padding(.top, Self.gap)
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
        }
    }

    /// The bubble behind a person's words: `bubblePerson` with its tail at
    /// the trailing foot; a queued message is a dashed outline, filled on
    /// hover; an answer is tinted with `question`.
    @ViewBuilder
    private var personBubble: some View {
        let shape = Self.bubble(tailLeading: false)
        if isQueued {
            shape.fill(isHovered ? palette[.controlHover] : .clear)
                .overlay { shape.stroke(palette[.stateQueued], style: StrokeStyle(lineWidth: 1, dash: [3, 2.5])) }
        } else if message.kind == .answer {
            shape.fill(palette[.question].opacity(0.15))
                .overlay { shape.strokeBorder(palette[.question].opacity(0.4), lineWidth: 1) }
        } else {
            shape.fill(palette[.bubblePerson])
        }
    }

    /// The quiet line under a person's message: its state (an answer says
    /// it went at once), the region tag, and the time.
    private var personLine: some View {
        HStack(spacing: 8) {
            if message.kind == .answer {
                Label("Answer · sent at once", systemImage: "checkmark")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(palette[.question])
                    .labelStyle(.titleAndIcon)
            } else if let state = message.state {
                StateChip(state: state, font: .subheadline.weight(.medium))
            }
            if message.region != nil {
                Label("Region", systemImage: "rectangle.dashed")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(palette[.regionOutline])
                    .labelStyle(.titleAndIcon)
            }
            time
        }
        .lineLimit(1)
        .fixedSize()
    }

    // MARK: - The agent's message

    private func agent(_ writer: MessageWriter) -> some View {
        HStack(alignment: .bottom, spacing: 8) {
            AgentAvatar(agent: writer.agent, size: Self.avatar, symbol: isQuestion ? "questionmark" : "sparkles", fill: avatarFill)
                .opacity(run.endsRun ? 1 : 0)
            VStack(alignment: .leading, spacing: 3) {
                if run.startsRun {
                    HStack(spacing: 0) {
                        Text(writer.name)
                            .fontWeight(.semibold)
                            .foregroundStyle(palette[.agent])
                        Text(" · ")
                        time
                    }
                    .font(.subheadline)
                    .foregroundStyle(palette[.textTertiary])
                    .lineLimit(1)
                    .padding(.leading, 4)
                }
                if isQuestion {
                    question(writer)
                } else {
                    words
                        .background(palette[.bubbleAgent], in: Self.bubble(tailLeading: true))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.trailing, Self.agentInset)
        // A run's later messages sit closer to the one before.
        .padding(.top, run.startsRun ? Self.gap : Self.gap / 2)
    }

    /// The agent's question: a card headed "<agent> asks", in
    /// `bubbleQuestion` with a border in `question`. One already answered
    /// is quieter.
    private func question(_ writer: MessageWriter) -> some View {
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: 14, bottomLeadingRadius: Self.tail, bottomTrailingRadius: 14, topTrailingRadius: 14, style: .continuous
        )
        return VStack(alignment: .leading, spacing: 4) {
            Label("\(writer.name) asks", systemImage: "questionmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(palette[.question])
                .labelStyle(.titleAndIcon)
                .lineLimit(1)
            Text(message.text)
                .font(.body)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.top, 9)
        .padding(.bottom, 10)
        .background(palette[.bubbleQuestion], in: shape)
        .overlay { shape.strokeBorder(palette[.question].opacity(0.32), lineWidth: 1) }
        .opacity(isOpenQuestion ? 1 : 0.8)
    }

    private var isQuestion: Bool { message.author == .agent && message.kind == .question }

    /// The avatar's fill with no logo: the agent's colour, or a question's.
    private var avatarFill: Color { isQuestion ? palette[.question] : palette[.agent] }

    // MARK: - Shared parts

    /// The words in a bubble's padding, hugging them as in a chat.
    private var words: some View {
        Text(message.text)
            .font(.body)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
    }

    /// A bubble: round corners, and the small one its tail is at the foot
    /// of the side its writer is on.
    static func bubble(tailLeading: Bool) -> UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: corner, bottomLeadingRadius: tailLeading ? tail : corner,
            bottomTrailingRadius: tailLeading ? corner : tail, topTrailingRadius: corner, style: .continuous
        )
    }

    private var time: some View {
        Text(message.at.formatted(.dateTime.hour().minute()))
            .font(.subheadline.monospacedDigit())
            .foregroundStyle(palette[.textTertiary])
    }

    /// The crop of a region message, as an attachment under its bubble.
    private func crop(_ file: URL) -> some View {
        SidebarPicture(file: file, side: Self.cropSize.width, shape: 16 / 9)
            .frame(maxWidth: Self.cropSize.width, maxHeight: Self.cropSize.height, alignment: .trailing)
            .help("The region this message points at")
            .accessibilityHidden(true)
            .padding(.top, 2)
    }

    /// The queued message edited in place: Return saves, Escape cancels.
    private func editor(_ text: String) -> some View {
        VStack(alignment: .trailing, spacing: 6) {
            MessageField(text: binding(text), placeholder: "Message", commit: save, cancel: { edited = nil })
                .frame(height: 60)
            HStack(spacing: 6) {
                Text("↩ save · esc cancel")
                    .font(.subheadline)
                    .foregroundStyle(palette[.textTertiary])
                Spacer()
                Button("Cancel") { edited = nil }
                    .pressedByKeys(in: model) { edited = nil }
                Button("Save", action: save)
                    .buttonStyle(.borderedProminent)
                    .pressedByKeys(in: model, action: save)
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
}

/// A message's state: its glyph and its name, in its colour, so a state is
/// never told by colour alone.
struct StateChip: View {
    let state: MessageState
    var font: Font = .caption.weight(.medium)
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: StateLook.glyph(state))
                .imageScale(.small)
            Text(StateLook.name(state))
        }
        .font(font)
        .foregroundStyle(palette.state(state))
        .lineLimit(1)
        .fixedSize()
        .accessibilityElement(children: .combine)
    }
}

/// A native borderless symbol button beside a message.
struct RowButton: View {
    @Environment(\.palette) private var palette

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
                .font(.system(size: 12, weight: .medium))
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .foregroundStyle(palette[.textSecondary])
        .help(title)
        .accessibilityLabel(title)
    }
}
