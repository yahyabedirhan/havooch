import ReviewCore
import ReviewWire
import SwiftUI

struct ThreadView: View {
    let model: WindowModel
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
                    Conversation(model: model, thread: thread, offersQuickReplies: true)
                    ThreadActivity(model: model, thread: thread.id)
                }
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 16 + MessageBubble.gap)
            }
            .defaultScrollAnchor(.bottom)
            .id(thread.id)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(thread.isGeneral ? "General thread" : "Thread \(thread.number)")
    }
}

struct Conversation: View {
    let model: WindowModel
    let thread: ReviewThread
    var offersQuickReplies = false

    var body: some View {
        let messages = thread.messages
        let open = thread.openQuestion?.id
        let choices = offersQuickReplies ? QuickReplies.choices(of: thread, isPointingAtRegion: model.isPointingAtRegion) : []
        ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
            MessageBubble(model: model, message: message, isOpenQuestion: message.id == open, run: ChatRun(of: index, in: messages))
            if message.id == open, !choices.isEmpty {
                QuickReplies(model: model, thread: thread.id, choices: choices)
            }
        }
    }
}

private struct ThreadViewBar: View {
    let model: WindowModel
    let thread: ReviewThread
    @Environment(\.palette) private var palette

    static let height: CGFloat = 44

    var body: some View {
        let others = model.othersNeedingYou
        ZStack {
            HStack(spacing: 0) {
                back(others)
                Spacer(minLength: 8)
                step("Previous thread", key: "↑", symbol: "chevron.up", forward: false)
                step("Next thread", key: "↓", symbol: "chevron.down", forward: true)
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
        .pressedByKeys(in: model) { _ = model.showThreadList() }
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

    private func step(_ title: String, key: String, symbol: String, forward: Bool) -> some View {
        Button {
            model.showNeighbour(forward: forward)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(palette[.textSecondary])
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .pressedByKeys(in: model) { model.showNeighbour(forward: forward) }
        .disabled(model.neighbour(forward: forward) == nil)
        .help("\(title) (\(key))")
        .accessibilityLabel(title)
    }
}

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
