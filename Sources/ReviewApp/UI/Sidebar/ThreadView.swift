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

/// The sidebar's view of one thread (L38): a top bar with Back, the
/// thread's number and time, and Previous and Next; the conversation; and
/// the field at the foot. No keyframe: the stage shows the thread's frame.
struct ThreadView: View {
    let model: AppModel
    let thread: ReviewThread

    var body: some View {
        VStack(spacing: 0) {
            ThreadViewBar(model: model, thread: thread)
            Hairline(axis: .horizontal)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if thread.messages.isEmpty {
                        GeneralIntro()
                    }
                    Conversation(model: model, thread: thread)
                }
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 16 + MessageBubble.gap)
            }
            // A conversation reads from its newest message, as in a chat.
            .defaultScrollAnchor(.bottom)
            // Each thread opens at its newest message.
            .id(thread.id)
            Hairline(axis: .horizontal)
            ThreadField(model: model, thread: thread)
                // Words written on one thread never go to another.
                .id(thread.id)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(thread.isGeneral ? "General thread" : "Thread \(thread.number)")
    }
}

/// A thread's messages as a chat (L40), in the order written: in the
/// thread view and in the thread popover alike.
struct Conversation: View {
    let model: AppModel
    let thread: ReviewThread

    var body: some View {
        let messages = thread.messages
        let open = thread.openQuestion?.id
        ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
            MessageBubble(model: model, message: message, isOpenQuestion: message.id == open, run: ChatRun(of: index, in: messages))
        }
    }
}

/// The top bar of a thread view: Back with the count of the other threads
/// that need the person, the thread's number and time in the middle, and
/// Previous and Next at the trailing end.
private struct ThreadViewBar: View {
    let model: AppModel
    let thread: ReviewThread
    @Environment(\.palette) private var palette

    static let height: CGFloat = 44

    var body: some View {
        let others = model.othersNeedingYou
        ZStack {
            HStack(spacing: 0) {
                back(others)
                Spacer(minLength: 8)
                step("Previous thread", symbol: "chevron.up", forward: false)
                step("Next thread", symbol: "chevron.down", forward: true)
            }
            title
        }
        .padding(.leading, 6)
        .padding(.trailing, 10)
        .frame(height: Self.height)
    }

    private func back(_ others: Int) -> some View {
        Button {
            _ = model.showThreadList()
        } label: {
            HStack(spacing: 2) {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                Text("Threads")
                if others > 0 {
                    Text("\(others)")
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(palette[.window])
                        .padding(.horizontal, 5)
                        .frame(minWidth: 17, minHeight: 17)
                        .background(palette[.question], in: Capsule())
                        .padding(.leading, 5)
                }
            }
            .foregroundStyle(palette[.accent])
            .padding(.horizontal, 4)
            .frame(height: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help("Back to the threads (Esc)")
        .accessibilityLabel(others > 0 ? "Threads, \(others) more \(others == 1 ? "needs" : "need") you" : "Threads")
        .accessibilityHint("Shows the thread list")
    }

    private var title: some View {
        let summary = ThreadSummary(thread, agent: model.agentName)
        return HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(summary.title)
                .font(.body.weight(.semibold).monospacedDigit())
            if let time = summary.time {
                Text(time)
                    .font(.body.monospacedDigit())
                    .foregroundStyle(palette[.textSecondary])
            }
        }
        .lineLimit(1)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .allowsHitTesting(false)
    }

    private func step(_ title: String, symbol: String, forward: Bool) -> some View {
        Button {
            model.showNeighbour(forward: forward)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(palette[.textSecondary])
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        // A native borderless button: it dims while pressed and when
        // disabled, and takes the focus ring with keyboard navigation.
        .buttonStyle(.borderless)
        .disabled(model.neighbour(forward: forward) == nil)
        .help(title)
        .accessibilityLabel(title)
    }
}

/// General with no message yet: what it is for.
private struct GeneralIntro: View {
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "globe")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(palette[.textSecondary])
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("General")
                    .font(.headline)
                Text("Notes on the whole video. They go with the next send, without a keyframe.")
                    .font(.callout)
                    .foregroundStyle(palette[.textSecondary])
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette[.well], in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// The field at the foot of a thread view: answers an open question at
/// once, else queues a follow-up. It waits for a click, so an answer that
/// arrives never takes the keys from the player.
private struct ThreadField: View {
    let model: AppModel
    let thread: ReviewThread

    @State private var words = ""
    @State private var isWriting = false
    @Environment(\.palette) private var palette

    var body: some View {
        let look = ThreadFieldLook(thread)
        VStack(alignment: .trailing, spacing: 6) {
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
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
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
