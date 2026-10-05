import SwiftUI
import VRReview

/// A comment's thread, under its row: the agent's messages and questions
/// on the leading side, the person's answers on the trailing side. A
/// question that waits is marked, and the answer box sits right under it,
/// only while it waits.
struct ThreadView: View {
    let model: AppModel
    let comment: Comment

    var body: some View {
        let waiting = comment.openQuestion == nil ? nil : comment.thread.lastIndex { $0.kind == .question }
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(comment.thread.enumerated()), id: \.offset) { index, message in
                MessageRow(message: message, waits: index == waiting)
            }
            if waiting != nil {
                AnswerBox(model: model, comment: comment.id)
            }
        }
    }
}

/// One thread message, as a soft chat bubble. The agent's sits on the
/// leading side under its name, on a quiet fill; a question is tinted honey
/// and, while it waits, says so and gets a hairline. The person's answer
/// sits on the trailing side, tinted with the accent colour.
struct MessageRow: View {
    let message: ThreadMessage
    /// Whether it is a question nobody has answered yet.
    var waits = false

    private var fromPerson: Bool { message.author == .person }
    private var asks: Bool { message.kind == .question }

    var body: some View {
        VStack(alignment: fromPerson ? .trailing : .leading, spacing: 2) {
            HStack(spacing: 4) {
                if !fromPerson {
                    Image(systemName: asks ? "questionmark.bubble.fill" : "sparkles")
                        .foregroundStyle(asks ? Theme.honey : Color.secondary)
                }
                Text(Self.who(message))
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
            }
            .font(.caption2)
            // The clock time is a hover away: beside the comments' video
            // times it would read as one of them.
            .help(message.at.formatted(date: .abbreviated, time: .shortened))
            Text(message.text)
                .font(.callout)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(bubble, in: RoundedRectangle(cornerRadius: Theme.bubbleCorner))
                .overlay {
                    if waits { RoundedRectangle(cornerRadius: Theme.bubbleCorner).strokeBorder(Theme.honey.opacity(0.6), lineWidth: 0.5) }
                }
            if waits {
                Label("Waiting for your answer", systemImage: "hourglass")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: fromPerson ? .trailing : .leading)
        .padding(fromPerson ? .leading : .trailing, 24)
        .accessibilityElement(children: .combine)
    }

    private var bubble: AnyShapeStyle {
        if fromPerson { return AnyShapeStyle(Color.accentColor.opacity(0.18)) }
        if asks { return AnyShapeStyle(Theme.honey.opacity(0.2)) }
        return AnyShapeStyle(.quaternary)
    }

    static func who(_ message: ThreadMessage) -> String {
        switch (message.author, message.kind) {
        case (.person, _): "You"
        case (.agent, .question): "Agent asks"
        case (.agent, _): "Agent"
        }
    }
}

/// Where the person answers the question that waits on a comment: a quiet
/// field on a soft fill, and a send button tinted with the accent colour
/// once there is something to send. Return sends the answer; it takes the
/// same way as `thread answer`.
private struct AnswerBox: View {
    let model: AppModel
    let comment: CommentID
    @State private var text = ""

    private var empty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            TextField("Answer…", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.callout)
                .lineLimit(1...5)
                .onSubmit(send)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(.quinary, in: RoundedRectangle(cornerRadius: Theme.bubbleCorner))
            Button(action: send) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundStyle(empty ? AnyShapeStyle(.tertiary) : AnyShapeStyle(Color.accentColor))
            }
            .buttonStyle(.plain)
            .disabled(empty)
            .help("Send your answer (Return)")
            .accessibilityLabel("Send answer")
        }
    }

    private func send() {
        guard !empty else { return }
        if model.answerForPerson(comment, text: text) { text = "" }
    }
}
