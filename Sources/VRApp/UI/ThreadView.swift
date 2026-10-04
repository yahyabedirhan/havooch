import SwiftUI
import VRReview

/// A thread inside a card: each message with who wrote it and what it is,
/// oldest first. The agent's side is tinted; the person's answer isn't.
struct ThreadView: View {
    let messages: [ThreadMessage]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(messages.enumerated()), id: \.offset) { _, message in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: Theme.glyph(for: message))
                        .font(.caption)
                        .foregroundStyle(Theme.colour(for: message))
                        .frame(width: 14)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(Theme.label(for: message))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(message.text)
                            .font(.callout)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// The box under an open question: the person's answer, sent with Return or
/// the button. It keeps its text when the answer is refused.
struct AnswerBox: View {
    /// Answers the question; false when it's refused.
    let answer: (String) -> Bool

    @State private var text = ""

    var body: some View {
        HStack(spacing: 6) {
            TextField("Answer the agent", text: $text, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...4)
                .onSubmit(send)
            Button("Answer", action: send)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private func send() {
        if answer(text) { text = "" }
    }
}
