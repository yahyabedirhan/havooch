import AppKit
import ReviewCore
import ReviewWire
import SwiftUI

/// The words of a thread's row in the thread list (L38): its name, its
/// frame's time, its state, how fresh it is and its last message.
struct ThreadSummary: Hashable {
    /// `#3`, or `General`.
    var title: String
    /// The frame's time as the player bar shows it (`0:12`); nil for General.
    var time: String?
    var state: MessageState?
    /// Who wrote the last message: `You`, `Asks` for the agent's question,
    /// or the agent's name. Nil with no message.
    var writer: String?
    /// Whether the agent wrote the last message: its logo leads the preview.
    var byAgent = false
    /// The last message's words on one line. General with no message says
    /// what it is for.
    var words: String
    /// When the last message was written; nil with no message.
    var lastAt: Date?
    /// Whether the agent waits for the person's answer on the thread.
    var waitsForAnswer: Bool
    /// The agent's name, for VoiceOver's reading of a question.
    private var agent: String

    init(_ thread: ReviewThread, agent: String) {
        self.agent = agent
        title = thread.isGeneral ? "General" : "#\(thread.number)"
        time = thread.time.map { TimeCode.text($0.rounded(.down)) }
        state = thread.state
        waitsForAnswer = thread.openQuestion != nil
        if let last = thread.messages.last {
            switch (last.author, last.kind) {
            case (.agent, .question): writer = "Asks"
            case (.agent, _): writer = agent
            case (.person, _): writer = "You"
            }
            byAgent = last.author == .agent
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

    /// The row as one line, for VoiceOver: the number, the time, the state
    /// and the preview. A question is read as the agent asking.
    var text: String {
        let state = waitsForAnswer ? "waiting for your answer" : self.state.map(StateLook.name)
        let preview = writer == "Asks" ? "\(agent) asks: \(words)" : self.preview
        return [title, time, state, preview].compactMap(\.self).joined(separator: ", ")
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

/// One thread in the thread list (L38): its keyframe thumbnail with its
/// regions, its number and time, its state, how fresh it is, and a
/// two-line preview of its last message. General has a symbol in the
/// keyframe's place. A click shows the thread's view and moves the player
/// to its frame. The row of the thread on the stage sits in a `well`.
struct ThreadRow: View {
    let model: AppModel
    let thread: ReviewThread
    /// Whether the thread's frame is on the stage.
    let isOnStage: Bool

    @State private var isHovered = false
    @Environment(\.palette) private var palette
    @Environment(\.colorScheme) private var colorScheme

    static let thumbnail = CGSize(width: 88, height: 50)
    /// The space between the thumbnail and the words.
    static let spacing: CGFloat = 11
    /// The row's inner padding at either side.
    static let padding: CGFloat = 10

    var body: some View {
        let summary = ThreadSummary(thread, agent: model.agentName)
        HStack(alignment: .top, spacing: Self.spacing) {
            picture
            VStack(alignment: .leading, spacing: 2) {
                firstLine(summary)
                preview(summary)
            }
        }
        .padding(.horizontal, Self.padding)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(fill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .animation(.smooth(duration: 0.12), value: isHovered)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture { model.showThread(thread.id) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary.text)
        .accessibilityHint("Shows the conversation")
        .accessibilityAddTraits(isOnStage ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { model.showThread(thread.id) }
    }

    /// The thread on the stage, else the one under the pointer.
    private var fill: Color {
        if isOnStage { return palette[.well] }
        return isHovered ? palette[.controlHover] : .clear
    }

    private func firstLine(_ summary: ThreadSummary) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(summary.title)
                .font(.body.weight(.semibold).monospacedDigit())
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
                        .foregroundStyle(palette[.textTertiary])
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
        let mark = summary.byAgent ? Text("\(agentMark) ") : Text("")
        return Text("\(mark)\(writer)\(summary.words)")
            .font(.callout)
            .foregroundStyle(palette[.textSecondary])
            .lineLimit(2, reservesSpace: false)
            .truncationMode(.tail)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// The agent's logo at the size of the preview's text, inside the
    /// line; the sparkle of an agent with no logo (`AgentAvatar`'s symbol).
    private var agentMark: Text {
        guard let agent = model.agent, let logo = AgentLogoImage.image(for: agent, dark: colorScheme == .dark),
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
