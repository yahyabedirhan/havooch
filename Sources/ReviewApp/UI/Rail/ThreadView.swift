import ReviewCore
import SwiftUI

/// The words of one thread message's heading: who said it, and how.
struct ThreadHeading: Equatable {
    /// "Claude Code asked", "You answered", "Claude Code".
    var title: String
    /// The symbol in the message's badge.
    var symbol: String

    init(_ message: ThreadMessage, agent: String) {
        switch (message.author, message.kind) {
        case (.agent, .question): (title, symbol) = ("\(agent) asked", "questionmark")
        case (.agent, _): (title, symbol) = (agent, "sparkles")
        case (.person, .answer): (title, symbol) = ("You answered", "person.fill")
        case (.person, _): (title, symbol) = ("You", "person.fill")
        }
    }
}

/// A thread: the agent's messages and questions and the person's answers,
/// in the order written, with the answer box under an open question. A
/// batch's own messages are drawn by the same view, with no answer box.
struct ThreadView: View {
    let messages: [ThreadMessage]
    /// The agent's name as people read it.
    let agent: String
    /// Sends the person's answer to the open question; false when it wasn't
    /// taken. Nil where there's nothing to answer (a batch's messages).
    var answer: ((String) -> Bool)?

    @State private var words = ""

    var body: some View {
        let open = answer == nil ? nil : messages.openQuestion
        VStack(alignment: .leading, spacing: 8) {
            ForEach(messages) { message in
                ThreadRow(message: message, agent: agent, isOpen: message.id == open?.id)
            }
            if open != nil, let answer {
                answerBox(answer)
            }
        }
    }

    /// The answer box: a text view that waits for a click, so a question
    /// that arrives never takes the keys from the player or from a comment
    /// being written.
    private func answerBox(_ answer: @escaping (String) -> Bool) -> some View {
        let send = {
            guard AppModel.hasWords(words) else { return }
            if answer(words) { words = "" }
        }
        return VStack(alignment: .trailing, spacing: 6) {
            CommentField(text: $words, placeholder: "Answer the question…", takesFocus: false, commit: send, cancel: { words = "" })
                .frame(height: 48)
            HStack(spacing: 8) {
                Text("↩ to answer")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("Answer", action: send)
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.question)
                    .controlSize(.small)
                    .disabled(!AppModel.hasWords(words))
            }
        }
        .padding(.leading, ThreadRow.indent)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Answer the agent's question")
    }
}

/// One message of a thread: a badge for its author, who said it and when,
/// and the words. An open question is picked out: the agent waits for it.
struct ThreadRow: View {
    let message: ThreadMessage
    let agent: String
    var isOpen = false

    private static let badge: CGFloat = 18
    /// Where a row's words start, which the answer box lines up with.
    static let indent: CGFloat = badge + 8

    var body: some View {
        let heading = ThreadHeading(message, agent: agent)
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: heading.symbol)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: Self.badge, height: Self.badge)
                .background(tint, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(heading.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(message.kind == .question ? AnyShapeStyle(Theme.question) : AnyShapeStyle(.secondary))
                    if isOpen {
                        Text("waiting for you")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Theme.question)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Theme.question.opacity(0.14), in: Capsule())
                    }
                    Spacer(minLength: 4)
                    Text(message.at.formatted(.dateTime.hour(.twoDigits(amPM: .abbreviated)).minute(.twoDigits)))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
                Text(message.text)
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var tint: Color {
        switch (message.author, message.kind) {
        case (.agent, .question): Theme.question
        case (.agent, _): Theme.agent
        case (.person, _): .gray
        }
    }
}
