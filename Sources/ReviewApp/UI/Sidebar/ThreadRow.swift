import AppKit
import ReviewCore
import ReviewWire
import SwiftUI

/// The words of a thread's row in the thread list: its name, its
/// frame's time, its state, how fresh it is and its last message.
struct ThreadSummary: Hashable {
    /// `#3`, or `General`.
    var title: String
    /// The frame's time as the player bar shows it (`0:12`); nil for General.
    var time: String?
    /// In a project, the version the thread was raised on: `v2`, or
    /// `Removed version`; nil on a plain video and for General.
    var version: String?
    var state: MessageState?
    /// Who wrote the last message: `You`, `Asks` for the agent's question,
    /// or the agent's name. Nil with no message.
    var writer: String?
    /// Whether the agent wrote the last message: its logo leads the preview.
    var byAgent = false
    /// The harness of the session that wrote the last message, for its
    /// logo; nil for the person's message or a name no agent has.
    var writerAgent: KnownAgent?
    /// The last message's words on one line. General with no message says
    /// what it is for.
    var words: String
    /// When the last message was written; nil with no message.
    var lastAt: Date?
    /// Whether the agent waits for the person's answer on the thread.
    var waitsForAnswer: Bool
    /// Whether an agent message came after the person last opened the
    /// thread's view: the row shows the unread dot.
    var isUnread: Bool
    /// The name of the agent that wrote the last message, for VoiceOver's
    /// reading of a question.
    private var agent: String

    /// `agent` names a message of the agent's kept with no session name.
    init(_ thread: ReviewThread, agent: String, version: VersionTag? = nil) {
        self.agent = agent
        title = thread.isGeneral ? "General" : "#\(thread.number)"
        self.version = version?.label
        time = thread.time.map { TimeCode.text($0.rounded(.down)) }
        state = thread.state
        waitsForAnswer = thread.openQuestion != nil
        isUnread = thread.isUnread
        if let last = thread.messages.last {
            let lastWriter = MessageWriter(last, listener: agent)
            switch (last.author, last.kind) {
            case (.agent, .question): writer = "Asks"
            case (.agent, _): writer = lastWriter.name
            case (.person, _): writer = "You"
            }
            byAgent = last.author == .agent
            writerAgent = lastWriter.agent
            if byAgent { self.agent = lastWriter.name }
            words = last.text.split(whereSeparator: \.isNewline).joined(separator: " ")
            lastAt = last.at
        } else {
            words = thread.isGeneral ? "Talk with the agent about the whole video" : "No messages"
        }
    }

    /// The last message with its writer: `You: Too fast here`.
    var preview: String {
        writer.map { "\($0): \(words)" } ?? words
    }

    /// The row as one line, for VoiceOver: unread first when it is, the
    /// number, the time, the state and the preview. A question is read as
    /// the agent asking.
    var text: String {
        let state = waitsForAnswer ? "waiting for your answer" : self.state.map(StateLook.name)
        let preview = writer == "Asks" ? "\(agent) asks: \(words)" : self.preview
        return [isUnread ? "Unread" : nil, title, version, time, state, preview].compactMap(\.self).joined(separator: ", ")
    }
}

/// What a row's menu offers; `WindowModel.rowActions` says which
/// apply to a thread.
enum RowAction: Identifiable {
    /// Shows the thread's view, as a click on the row does.
    case open
    /// Moves the player to the thread's frame and leaves the list showing.
    case showOnVideo
    /// Deletes the thread's queued messages.
    case deleteQueued

    var id: Self { self }

    var title: String {
        switch self {
        case .open: "Open"
        case .showOnVideo: "Show on Video"
        case .deleteQueued: "Delete Queued Messages"
        }
    }

    var symbol: String {
        switch self {
        case .open: "arrow.right.circle"
        case .showOnVideo: "play.rectangle"
        case .deleteQueued: "trash"
        }
    }
}

/// How long ago a thread's last message was written, as a row shows it:
/// `now`, `3m`, `2h`, `4d`.
enum RelativeTime {
    static func short(_ date: Date, now: Date) -> String {
        let seconds = max(now.timeIntervalSince(date), 0)
        switch seconds {
        case ..<45: return "now"
        case ..<3600: return "\(max(Int(seconds / 60), 1))m"
        case ..<86400: return "\(Int(seconds / 3600))h"
        default: return "\(Int(seconds / 86400))d"
        }
    }
}

/// One thread in the thread list: its keyframe thumbnail with its
/// regions, its number and time, its state, how fresh it is, and a
/// two-line preview of its last message. General has a symbol in the
/// keyframe's place. A click shows the thread's view and moves the player
/// to its frame. The row of the thread on the stage sits in a `well`.
/// An unread row  has an 8 pt dot in the accent colour at its left,
/// its title bold, its preview in the primary text colour and its time in
/// the accent colour.
/// Keyboard navigation reaches the row, with the system focus ring, and
/// Space or Return opens it as a click does.
struct ThreadRow: View {
    let model: WindowModel
    let thread: ReviewThread
    /// Whether the thread's frame is on the stage.
    let isOnStage: Bool
    /// Whether the row shows its version's tag; a version section of a
    /// project's list names the version in its header instead.
    /// VoiceOver reads the version either way.
    var showsVersion = true
    /// Whether the thread was raised on another version than the one on
    /// screen: its keyframe and its title are quieter, nothing else
    /// changes (thread-list V5).
    var isOffVersion = false

    @State private var isHovered = false
    @Environment(\.palette) private var palette
    @Environment(\.colorScheme) private var colorScheme

    static let thumbnail = CGSize(width: 88, height: 50)
    /// The space between the thumbnail and the words.
    static let spacing: CGFloat = 11
    /// The row's inner padding at either side.
    static let padding: CGFloat = 10
    /// The unread dot's diameter.
    static let unreadDot: CGFloat = 8

    var body: some View {
        let summary = ThreadSummary(thread, agent: model.agentName, version: model.versionTag(of: thread))
        // A button, so keyboard navigation reaches the row and the system
        // draws its focus ring; the style keeps the row's own look.
        Button { model.perform(.open, on: thread.id) } label: {
            HStack(alignment: .top, spacing: Self.spacing) {
                picture
                    .opacity(isOffVersion ? 0.55 : 1)
                    .saturation(isOffVersion ? 0.3 : 1)
                VStack(alignment: .leading, spacing: 2) {
                    firstLine(summary)
                    preview(summary)
                }
            }
            .padding(.horizontal, Self.padding)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fill, in: Self.shape)
            .overlay(alignment: .topLeading) {
                if summary.isUnread { unreadDot }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(RowButtonStyle())
        .contentShape(.focusEffect, Self.shape)
        .pressedByKeys(in: model) { model.perform(.open, on: thread.id) }
        .animation(.smooth(duration: 0.12), value: isHovered)
        .onHover { isHovered = $0 }
        .contextMenu {
            ForEach(model.rowActions(for: thread)) { action in
                Button(action.title, systemImage: action.symbol, role: action == .deleteQueued ? .destructive : nil) {
                    model.perform(action, on: thread.id)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary.text)
        .accessibilityHint("Shows the conversation")
        .accessibilityAddTraits(isOnStage ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { model.perform(.open, on: thread.id) }
        .accessibilityActions {
            ForEach(model.rowActions(for: thread).filter { $0 != .open }) { action in
                Button(action.title) { model.perform(action, on: thread.id) }
            }
        }
    }

    /// The row's outline: its fill, and the focus ring around it.
    private static let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)

    /// The thread on the stage, else the one under the pointer.
    private var fill: Color {
        if isOnStage { return palette[.well] }
        return isHovered ? palette[.controlHover] : .clear
    }

    private func firstLine(_ summary: ThreadSummary) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(summary.title)
                .font(.body.weight(summary.isUnread ? .bold : .semibold).monospacedDigit())
                .foregroundStyle(palette[isOffVersion ? .textSecondary : .textPrimary])
            if showsVersion, let version = summary.version {
                // The version's tag: a soft fill, no edge (look rules).
                Text(version)
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(palette[.textSecondary])
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(palette[.well], in: Capsule())
                    .lineLimit(1)
                    .fixedSize()
            }
            if let time = summary.time {
                Text(time)
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(palette[.textSecondary])
            }
            if summary.waitsForAnswer {
                Label("Answer", systemImage: "questionmark.circle.fill")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(palette[.question])
                    .labelStyle(.titleAndIcon)
                    .lineLimit(1)
                    .fixedSize()
            } else if let state = summary.state {
                StateChip(state: state)
            }
            Spacer(minLength: 4)
            if let at = summary.lastAt {
                // The relative time moves on while the row shows.
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Text(RelativeTime.short(at, now: context.date))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(palette[summary.isUnread ? .accent : .textTertiary])
                        .fixedSize()
                }
            }
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(palette[.textTertiary])
        }
        .frame(height: 18)
    }

    /// The last message on two lines, its writer in a quieter colour; the
    /// agent's logo leads a message of the agent's.
    private func preview(_ summary: ThreadSummary) -> some View {
        let writer = summary.writer.map { Text("\($0): ").foregroundStyle(palette[.textTertiary]) } ?? Text("")
        let mark = summary.byAgent ? Text("\(agentMark(summary.writerAgent)) ") : Text("")
        return Text("\(mark)\(writer)\(summary.words)")
            .font(.callout)
            .foregroundStyle(palette[summary.isUnread ? .textPrimary : .textSecondary])
            .lineLimit(2, reservesSpace: false)
            .truncationMode(.tail)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// The unread dot, centred in the gap at the row's left and on its
    /// first line; it straddles the row's edge so the thumbnail keeps its
    /// place.
    private var unreadDot: some View {
        Circle()
            .fill(palette[.accent])
            .frame(width: Self.unreadDot, height: Self.unreadDot)
            // The first line is 18 pt high, under the row's 8 pt top padding.
            .offset(x: -Self.unreadDot / 2 + 1, y: 8 + (18 - Self.unreadDot) / 2)
            .accessibilityHidden(true)
    }

    /// The agent's logo at the size of the preview's text, inside the
    /// line; the sparkle of an agent with no logo (`AgentAvatar`'s symbol).
    private func agentMark(_ agent: KnownAgent?) -> Text {
        guard let agent, let logo = AgentLogoImage.image(for: agent, dark: colorScheme == .dark),
              let small = logo.copy() as? NSImage
        else {
            return Text(Image(systemName: "sparkles")).foregroundStyle(palette[.agent])
        }
        small.size = NSSize(width: 11, height: 11)
        return Text(Image(nsImage: small)).baselineOffset(-1).foregroundStyle(palette[.textPrimary])
    }

    @ViewBuilder
    private var picture: some View {
        if thread.isGeneral {
            Image(systemName: "globe")
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(palette[.textSecondary])
                .frame(width: Self.thumbnail.width, height: Self.thumbnail.height)
                .background(palette[.well], in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .accessibilityHidden(true)
        } else {
            SidebarPicture(
                file: model.keyframe(of: thread), side: Self.thumbnail.width, regions: thread.messages.compactMap(\.region)
            )
            .frame(width: Self.thumbnail.width, height: Self.thumbnail.height)
        }
    }
}

/// A thread row's button: the row as it is drawn, with no button chrome
/// and no look of its own while pressed. The system focus ring still goes
/// around it under keyboard navigation.
private struct RowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}
