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
/// sidebar's `Conversation`, in the order written, the newest at the
/// foot. One message style in both places, and both read the same thread,
/// so a message written in either shows in both.
struct PopoverConversation: View {
    let model: AppModel
    let thread: ReviewThread
    /// Whether the conversation takes the room the popover has, in a
    /// popover the person sized; else it grows to `conversationHeight`.
    let fills: Bool

    @State private var contentHeight: CGFloat = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Conversation(model: model, thread: thread)
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
