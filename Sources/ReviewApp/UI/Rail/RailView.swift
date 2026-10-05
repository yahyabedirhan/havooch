import ReviewCore
import ReviewWire
import SwiftUI

/// The rail beside the stage: the General thread when it has messages,
/// then each thread in time order, with its messages in the order written.
/// The footer under it is the root view's (`SidebarFooter`).
///
/// Nothing in the rail is a bordered card. Each thread starts with a
/// header band, the person's messages are rows, and only the agent's
/// messages and the answers sit in bubbles, as in a chat.
struct RailView: View {
    let model: AppModel

    /// One part of a thread's conversation: a person's message, drawn as
    /// a row, or a run of the agent's messages and the answers, drawn as
    /// bubbles.
    enum Part: Identifiable {
        case work(Message)
        case talk([Message])

        var id: String {
            switch self {
            case .work(let message): message.id.text
            case .talk(let messages): "talk-" + (messages.first?.id.text ?? "")
            }
        }
    }

    /// `messages` cut into parts, in the order written.
    static func parts(of messages: [Message]) -> [Part] {
        var parts: [Part] = []
        for message in messages {
            if message.isWork {
                parts.append(.work(message))
            } else if case .talk(let run) = parts.last {
                parts[parts.count - 1] = .talk(run + [message])
            } else {
                parts.append(.talk([message]))
            }
        }
        return parts
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.palette) private var palette

    var body: some View {
        let threads = model.threads.filter { !$0.messages.isEmpty }
        if threads.isEmpty {
            empty
        } else {
            list(threads)
        }
    }

    private func list(_ threads: [ReviewThread]) -> some View {
        ScrollViewReader { scroll in
            ScrollView {
                // Not lazy: a review has tens of threads, not thousands,
                // and a row that changes state must be drawn again.
                VStack(spacing: 0) {
                    ForEach(threads) { thread in
                        section(thread)
                            .id(thread.id)
                    }
                }
                .padding(.bottom, 12)
            }
            .onChange(of: model.selection) { _, selection in
                guard let selection else { return }
                if reduceMotion {
                    scroll.scrollTo(selection)
                } else {
                    withAnimation(.smooth(duration: 0.35)) { scroll.scrollTo(selection) }
                }
            }
        }
    }

    /// One thread: its header band, then its conversation.
    private func section(_ thread: ReviewThread) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader { threadTitle(thread) }
                .contentShape(Rectangle())
                .onTapGesture { model.select(thread.id) }
            ForEach(Self.parts(of: thread.messages)) { part in
                switch part {
                case .work(let message):
                    CommentRow(model: model, message: message, thread: thread)
                case .talk(let messages):
                    ThreadView(messages: messages, openQuestion: thread.openQuestion, agent: model.agentName) {
                        model.answerQuestion(thread.id, text: $0)
                    }
                    .padding(.horizontal, Metrics.railPadding)
                    .padding(.vertical, 12)
                }
            }
        }
    }

    /// A section's header: a full-width band behind the title, as a list's
    /// section header, with no border.
    private func sectionHeader<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            content()
        }
        .padding(.horizontal, Metrics.railPadding)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette[.sidebarSection])
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    /// A thread's title: its number and frame, or General, and its state.
    @ViewBuilder
    private func threadTitle(_ thread: ReviewThread) -> some View {
        MarkerPin(
            number: thread.number, state: thread.state ?? .queued, isSelected: model.selection == thread.id,
            badge: MarkerPin.Badge(thread, unread: model.unread)
        )
        Text(thread.time.map { TimeCode.text($0) } ?? "General")
            .font(.subheadline.weight(.semibold).monospacedDigit())
        Spacer(minLength: 8)
        if let state = thread.state {
            StateChip(state: state)
        }
    }

    private var empty: some View {
        VStack(spacing: 8) {
            Image(systemName: "text.bubble")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(palette[.textTertiary])
                .padding(.bottom, 2)
            Text("No threads yet")
                .font(.headline)
            Text("Press C to write on the frame you're watching, or drag on the frame to point at a part of it. Each frame gets its thread; your messages queue, then go to your agent at once.")
                .font(.callout)
                .foregroundStyle(palette[.textSecondary])
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
