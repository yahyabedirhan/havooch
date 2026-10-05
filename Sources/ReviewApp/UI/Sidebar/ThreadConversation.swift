import ReviewCore
import ReviewWire
import SwiftUI

/// What the field at the foot of a thread does with its words (L14): the
/// answer to the agent's open question goes at once (D 2.16); anything
/// else is a follow-up in the queue (D 2.13).
struct ThreadFieldLook: Equatable {
    var placeholder: String
    var hint: String
    var button: String
    var answers: Bool

    init(_ thread: ReviewThread) {
        answers = thread.openQuestion != nil
        if answers {
            (placeholder, hint, button) = ("Answer the question…", "↩ answers at once", "Answer")
        } else if thread.isGeneral {
            (placeholder, hint, button) = ("Write to the agent…", "↩ queues · ⌘↩ sends the queue", "Queue")
        } else {
            (placeholder, hint, button) = ("Follow up on #\(thread.number)…", "↩ queues · ⌘↩ sends the queue", "Queue")
        }
    }
}

/// One expanded thread in the sidebar (D 3.3 to D 3.6): a header with its
/// number, time and state over its keyframe, the messages in order, and a
/// field at the foot. A click on the header collapses it; a click on the
/// keyframe opens the thread's popover on its frame.
struct ThreadConversation: View {
    let model: AppModel
    let thread: ReviewThread

    @State private var words = ""
    @State private var isWriting = false
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            VStack(alignment: .leading, spacing: 12) {
                if !thread.isGeneral {
                    keyframe
                }
                ForEach(thread.messages) { message in
                    MessageBubble(model: model, message: message, isOpenQuestion: message.id == thread.openQuestion?.id)
                }
                field
            }
            .padding(.horizontal, Metrics.sidebarPadding)
            .padding(.top, 10)
            .padding(.bottom, 14)
        }
        .background(palette[.sidebarRowSelected])
        .accessibilityElement(children: .contain)
        .accessibilityLabel(thread.isGeneral ? "General thread" : "Thread \(thread.number)")
    }

    /// The thread's number, time and state; a click collapses it.
    private var header: some View {
        let summary = ThreadSummary(thread, agent: model.agentName)
        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "chevron.down")
                .font(.caption.weight(.semibold))
                .foregroundStyle(palette[.textTertiary])
                .accessibilityHidden(true)
            Text(summary.title)
                .font(.subheadline.weight(.semibold).monospacedDigit())
            if let time = summary.time {
                Text(time)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(palette[.textSecondary])
            } else {
                Text("the whole video")
                    .font(.subheadline)
                    .foregroundStyle(palette[.textSecondary])
            }
            Spacer(minLength: 4)
            if let state = summary.state {
                StateChip(state: state)
            }
        }
        .padding(.horizontal, Metrics.sidebarPadding)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette[.sidebarSection])
        .contentShape(Rectangle())
        .onTapGesture { model.expandThread(thread.id) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits([.isHeader, .isButton])
        .accessibilityHint("Collapses the thread")
    }

    /// The thread's keyframe, whole; a click opens the thread's popover on
    /// its frame, as its pin does.
    private var keyframe: some View {
        Button {
            model.openThread(thread.id)
        } label: {
            SidebarPicture(file: model.keyframe(of: thread), side: Metrics.sidebarWidthRange.upperBound, corner: 8, shape: 16 / 9)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .help("Open this thread on the video")
        .accessibilityLabel("Keyframe of thread \(thread.number)")
        .accessibilityHint("Opens the thread's popover on its frame")
    }

    /// The field at the foot: answers an open question at once, else queues
    /// a follow-up. It waits for a click, so an answer that arrives never
    /// takes the keys from the player.
    private var field: some View {
        let look = ThreadFieldLook(thread)
        return VStack(alignment: .trailing, spacing: 6) {
            MessageField(text: $words, placeholder: look.placeholder, takesFocus: false, commit: write, cancel: { words = "" })
                .frame(height: 48)
            HStack(spacing: 8) {
                Text(look.hint)
                    .font(.caption)
                    .foregroundStyle(palette[.textTertiary])
                Spacer()
                Button(look.button, action: write)
                    .buttonStyle(.borderedProminent)
                    .tint(look.answers ? palette[.question] : palette[.accent])
                    .controlSize(.small)
                    .disabled(!AppModel.hasWords(words) || isWriting)
            }
        }
        .padding(.top, 2)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(look.answers ? "Answer the agent's question" : "Write on this thread")
    }

    private func write() {
        guard AppModel.hasWords(words), !isWriting else { return }
        let text = words
        isWriting = true
        Task {
            defer { isWriting = false }
            if await model.writeOnThread(thread.id, text: text), words == text { words = "" }
        }
    }
}
