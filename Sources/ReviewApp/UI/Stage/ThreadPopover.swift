import ReviewCore
import SwiftUI

/// Where a thread's popover sits on the stage once the person moved or
/// resized it (D 2.8, D 2.10). The thread keeps the rectangle in 0 to 1 of
/// the video area, so it lands in the same place at any window size; on
/// screen it is never smaller than it can be used at, nor outside the area.
enum ThreadPopover {
    /// The smallest the person can make the popover: the header, a line of
    /// the conversation, the field and its hints.
    static let minimumSize = CGSize(width: 280, height: 190)
    /// The space the popover keeps from the stage's edges.
    static let margin: CGFloat = 8
    /// How tall the conversation grows before it scrolls, in a popover at
    /// its own size.
    static let conversationHeight: CGFloat = 200

    /// The rectangle `frame` names on a stage `stage` in size, fitted in it.
    static func rect(of frame: PopoverFrame, in stage: CGSize) -> CGRect {
        fit(
            CGRect(x: frame.x * stage.width, y: frame.y * stage.height, width: frame.w * stage.width, height: frame.h * stage.height),
            in: stage
        )
    }

    /// `rect` on a stage `stage` in size, as the thread keeps it: fitted
    /// first, so a kept frame is always one the popover can be shown at.
    static func frame(of rect: CGRect, in stage: CGSize) -> PopoverFrame {
        let fitted = fit(rect, in: stage)
        guard stage.width > 0, stage.height > 0 else { return PopoverFrame(x: 0, y: 0, w: 1, h: 1) }
        return PopoverFrame(
            x: fitted.minX / stage.width, y: fitted.minY / stage.height,
            w: fitted.width / stage.width, h: fitted.height / stage.height
        )
    }

    /// `rect` made no smaller than `minimumSize` and no larger than the
    /// stage less its margins, then moved inside them.
    static func fit(_ rect: CGRect, in stage: CGSize) -> CGRect {
        let room = CGSize(width: max(stage.width - 2 * margin, 0), height: max(stage.height - 2 * margin, 0))
        let width = min(max(rect.width, minimumSize.width), room.width)
        let height = min(max(rect.height, minimumSize.height), room.height)
        let x = min(max(rect.minX, margin), max(stage.width - margin - width, margin))
        let y = min(max(rect.minY, margin), max(stage.height - margin - height, margin))
        return CGRect(x: x, y: y, width: width, height: height)
    }
}

/// A thread's conversation in its popover, above the field (D 2.7): the
/// person's messages on the right with their state, the agent's on the
/// left, a question picked out, the newest at the foot.
///
/// NOTE: The sidebar draws a thread's messages with views of its own. The
/// two read the same thread, so a message written in either shows in both.
struct PopoverConversation: View {
    let thread: ReviewThread
    /// The agent's name as people read it.
    let agent: String
    /// Whether the conversation takes the room the popover has, in a
    /// popover the person sized; else it grows to `conversationHeight`.
    let fills: Bool

    @State private var contentHeight: CGFloat = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(thread.messages) { message in
                    PopoverMessage(message: message, agent: agent, isOpen: message.id == thread.openQuestion?.id)
                }
            }
            .padding(.vertical, 2)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        }
        .defaultScrollAnchor(.bottom)
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxHeight: fills ? .infinity : min(max(contentHeight, 1), ThreadPopover.conversationHeight))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Thread \(thread.number)")
    }
}

/// One message in the popover's conversation: who wrote it and, for the
/// person's, its state; then the words in a bubble.
private struct PopoverMessage: View {
    let message: Message
    let agent: String
    /// Whether this is the question the agent waits on.
    let isOpen: Bool
    @Environment(\.palette) private var palette

    private var byPerson: Bool { message.author == .person }

    var body: some View {
        HStack(spacing: 0) {
            if byPerson { Spacer(minLength: 28) }
            VStack(alignment: byPerson ? .trailing : .leading, spacing: 3) {
                caption
                Text(message.text)
                    .font(.callout)
                    .foregroundStyle(palette[.textPrimary])
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(bubble, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            if !byPerson { Spacer(minLength: 28) }
        }
        .accessibilityElement(children: .combine)
    }

    /// "You · Queued", "Claude Code", "Claude Code asked · waiting for you".
    private var caption: some View {
        HStack(spacing: 4) {
            if message.region != nil {
                Image(systemName: "rectangle.dashed")
                    .foregroundStyle(palette[.textTertiary])
                    .accessibilityLabel("On a region")
            }
            Text(title)
                .fontWeight(.semibold)
                .foregroundStyle(message.kind == .question ? palette[.question] : palette[.textSecondary])
            if let state = message.state {
                Image(systemName: StateLook.glyph(state))
                    .imageScale(.small)
                    .foregroundStyle(palette.state(state))
                    .accessibilityHidden(true)
                Text(StateLook.name(state))
                    .foregroundStyle(palette.state(state))
            } else if isOpen {
                Text("waiting for you")
                    .foregroundStyle(palette[.question])
            }
        }
        .font(.caption2)
    }

    private var title: String {
        switch (message.author, message.kind) {
        case (.agent, .question): "\(agent) asked"
        case (.agent, _): agent
        case (.person, .answer): "You answered"
        case (.person, _): "You"
        }
    }

    private var bubble: Color {
        switch (message.author, message.kind) {
        case (.agent, .question): palette[.bubbleQuestion]
        case (.agent, _): palette[.bubbleAgent]
        case (.person, _): palette[.bubblePerson]
        }
    }
}

/// The grip in the popover's lower right corner that resizes it.
struct ResizeGrip: View {
    @Environment(\.palette) private var palette

    var body: some View {
        Image(systemName: "arrow.down.right.and.arrow.up.left")
            .font(.system(size: 8, weight: .semibold))
            .rotationEffect(.degrees(90))
            .foregroundStyle(palette[.textTertiary])
            .frame(width: 16, height: 16)
            .contentShape(Rectangle())
            .help("Drag to resize")
            .accessibilityLabel("Resize")
    }
}
