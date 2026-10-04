import SwiftUI
import VRReview

/// A comment's thread, under its card: the agent's messages and questions
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

/// One thread message. The agent's is a bubble on the leading side under
/// its name; a question is tinted and says whether it still waits. The
/// person's answer is a filled bubble on the trailing side.
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
                        .foregroundStyle(asks ? Color.purple : Color.accentColor)
                }
                Text(Self.who(message))
                    .fontWeight(.semibold)
                    .foregroundStyle(asks ? AnyShapeStyle(Color.purple) : AnyShapeStyle(.secondary))
            }
            .font(.caption2)
            // The clock time is a hover away: beside the comments' video
            // times it would read as one of them.
            .help(message.at.formatted(date: .abbreviated, time: .shortened))
            Text(message.text)
                .font(.callout)
                .foregroundStyle(fromPerson ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(bubble, in: RoundedRectangle(cornerRadius: 9))
                .overlay {
                    if asks { RoundedRectangle(cornerRadius: 9).strokeBorder(Color.purple.opacity(waits ? 0.9 : 0.35), lineWidth: waits ? 1.5 : 1) }
                }
            if waits {
                Label("Waiting for your answer", systemImage: "hourglass")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.purple)
            }
        }
        .frame(maxWidth: .infinity, alignment: fromPerson ? .trailing : .leading)
        .padding(fromPerson ? .leading : .trailing, 24)
        .accessibilityElement(children: .combine)
    }

    private var bubble: AnyShapeStyle {
        if fromPerson { return AnyShapeStyle(Color.accentColor) }
        if asks { return AnyShapeStyle(Color.purple.opacity(0.14)) }
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

/// Where the person answers the question that waits on a comment. Return
/// sends the answer; it takes the same way as `thread answer`.
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
                .background(.background, in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Color.purple.opacity(0.6)))
            Button(action: send) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundStyle(empty ? AnyShapeStyle(.tertiary) : AnyShapeStyle(Color.purple))
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
