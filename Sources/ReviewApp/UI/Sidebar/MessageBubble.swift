import AppKit
import ReviewCore
import SwiftUI

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

struct ChatRun: Equatable {
    var startsRun = false
    var endsRun = false

    init(of index: Int, in messages: [Message]) {
        guard messages.indices.contains(index), messages[index].author == .agent else { return }
        startsRun = index == messages.startIndex || messages[index - 1].author != .agent
        endsRun = index == messages.index(before: messages.endIndex) || messages[index + 1].author != .agent
    }
}

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

struct MessageBubble: View {
    let model: WindowModel
    let message: Message
    var isOpenQuestion = false
    var run: ChatRun

    @State private var edited: String?
    @State private var isHovered = false
    @State private var isEditFocused = false
    @State private var isDeleteFocused = false
    @Environment(\.palette) private var palette

    static let avatar: CGFloat = 24
    static let personInset: CGFloat = 46
    static let agentInset: CGFloat = 34
    static let gap: CGFloat = 8
    static let corner: CGFloat = 16
    static let tail: CGFloat = 5
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

    private var isQueued: Bool { message.isWork && message.state?.isEditable == true }

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
        .padding(.top, run.startsRun ? Self.gap : Self.gap / 2)
    }

    private func question(_ writer: MessageWriter) -> some View {
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: 14, bottomLeadingRadius: Self.tail, bottomTrailingRadius: 14, topTrailingRadius: 14, style: .continuous
        )
        return Text(message.text)
            .font(.body)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .accessibilityLabel("\(writer.name) asks: \(message.text)")
        .background(palette[.bubbleQuestion], in: shape)
        .overlay { shape.strokeBorder(palette[.question].opacity(0.32), lineWidth: 1) }
        .opacity(isOpenQuestion ? 1 : 0.8)
    }

    private var isQuestion: Bool { message.author == .agent && message.kind == .question }

    private var avatarFill: Color { isQuestion ? palette[.question] : palette[.agent] }

    private var words: some View {
        Text(message.text)
            .font(.body)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
    }

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

    private func crop(_ file: URL) -> some View {
        SidebarPicture(file: file, side: Self.cropSize.width, shape: 16 / 9)
            .frame(maxWidth: Self.cropSize.width, maxHeight: Self.cropSize.height, alignment: .trailing)
            .help("The region this message points at")
            .accessibilityHidden(true)
            .padding(.top, 2)
    }

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
                    .filledButton(palette)
                    .pressedByKeys(in: model, action: save)
                    .disabled(!WindowModel.hasWords(text))
            }
            .controlSize(.small)
        }
    }

    private func binding(_ text: String) -> Binding<String> {
        Binding(get: { edited ?? text }, set: { edited = $0 })
    }

    private func save() {
        guard let edited, WindowModel.hasWords(edited) else { return }
        model.edit(message.id, text: edited)
        self.edited = nil
    }
}

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
