import ReviewCore
import SwiftUI

/// Where a thread's popover sits on the stage once the person moved or
/// resized it (D 2.8, D 2.10). The thread keeps the rectangle in 0 to 1 of
/// the video area, so it lands in the same place at any window size; on
/// screen it is never smaller than it can be used at, nor outside the area.
/// The person resizes it from each edge and each corner, as a window
/// (`Drag`, `ResizeRules`, L70).
enum ThreadPopover {
    /// The smallest the person can make the popover: the header, a few
    /// lines of the conversation, the field and the band with its split
    /// button, unclipped.
    static let minimumSize = CGSize(width: 340, height: 320)
    /// The space the popover keeps from the stage's edges.
    static let margin: CGFloat = 8
    /// How tall the conversation grows before it scrolls, in a popover at
    /// its own size.
    static let conversationHeight: CGFloat = 200
    /// The least the conversation takes in a popover at its own size: the
    /// room it has at `minimumSize`, so the popover never opens smaller
    /// than the person could make it.
    static let conversationLeast: CGFloat = 180

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

    /// The size rules a thread's popover resizes by (L70): the header, a
    /// line of the conversation, the field and the band always show.
    static let rules = ResizeRules(minimum: minimumSize, maximum: CGSize(width: 640, height: 560))

    /// A drag on a thread's popover under way: on its header, which moves
    /// it, or on an edge or a corner, which resizes it. It keeps the
    /// rectangle the popover had as the drag began, so every step of the
    /// drag is measured from that one rectangle and never from the size
    /// the drag itself gave the popover.
    struct Drag: Equatable {
        /// The edge or the corner it holds; nil for the header.
        var handle: FrameResizePosition?
        /// The popover as the drag began, on the stage.
        var start: CGRect
        /// How far the pointer has gone.
        var translation: CGSize = .zero

        /// The popover for this drag on a stage `stage` in size: moved
        /// inside the stage's margins, or resized by `rules` with every
        /// moved edge inside them.
        func rect(in stage: CGSize) -> CGRect {
            guard let handle else {
                return fit(start.offsetBy(dx: translation.width, dy: translation.height), in: stage)
            }
            let room = CGRect(origin: .zero, size: stage).insetBy(dx: margin, dy: margin)
            return rules.resized(fit(start, in: stage), from: handle, by: translation, in: room)
        }
    }
}

/// The size rules a popover resizes by, as a window does (L70): a moved
/// edge follows the pointer, the edge across from it stays, and the size
/// stays between `minimum` and `maximum`.
struct ResizeRules: Equatable {
    let minimum: CGSize
    let maximum: CGSize

    /// `start` with the edges of `handle` moved by `translation`. `bounds`
    /// holds every moved edge in, and `covers` is a span along x the box
    /// keeps above it (the notch), so a side edge never passes it.
    func resized(
        _ start: CGRect, from handle: FrameResizePosition, by translation: CGSize, in bounds: CGRect,
        covers: ClosedRange<CGFloat>? = nil
    ) -> CGRect {
        let sides = ResizeSides(handle)
        var (minX, maxX, minY, maxY) = (start.minX, start.maxX, start.minY, start.maxY)
        if sides.contains(.leading) {
            var high = maxX - minimum.width
            if let covers { high = min(high, covers.lowerBound) }
            let low = min(max(maxX - maximum.width, bounds.minX), high)
            minX = min(max(start.minX + translation.width, low), high)
        }
        if sides.contains(.trailing) {
            var low = minX + minimum.width
            if let covers { low = max(low, covers.upperBound) }
            let high = max(min(minX + maximum.width, bounds.maxX), low)
            maxX = min(max(start.maxX + translation.width, low), high)
        }
        if sides.contains(.top) {
            let high = maxY - minimum.height
            let low = min(max(maxY - maximum.height, bounds.minY), high)
            minY = min(max(start.minY + translation.height, low), high)
        }
        if sides.contains(.bottom) {
            let low = minY + minimum.height
            let high = max(min(minY + maximum.height, bounds.maxY), low)
            maxY = min(max(start.maxY + translation.height, low), high)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// Which ways the resize pointer of `handle` says a box of `size` can
    /// still go: outward only at the minimum, inward only at the maximum.
    func directions(_ handle: FrameResizePosition, size: CGSize) -> FrameResizeDirection.Set {
        let sides = ResizeSides(handle)
        var grows = false, shrinks = false
        if !sides.isDisjoint(with: [.leading, .trailing]) {
            grows = grows || size.width < maximum.width - 0.5
            shrinks = shrinks || size.width > minimum.width + 0.5
        }
        if !sides.isDisjoint(with: [.top, .bottom]) {
            grows = grows || size.height < maximum.height - 0.5
            shrinks = shrinks || size.height > minimum.height + 0.5
        }
        switch (grows, shrinks) {
        case (true, false): return .outward
        case (false, true): return .inward
        default: return .all
        }
    }
}

/// The sides of a popover an edge or a corner moves.
private struct ResizeSides: OptionSet {
    let rawValue: Int
    static let top = ResizeSides(rawValue: 1)
    static let leading = ResizeSides(rawValue: 2)
    static let bottom = ResizeSides(rawValue: 4)
    static let trailing = ResizeSides(rawValue: 8)

    init(rawValue: Int) { self.rawValue = rawValue }

    init(_ handle: FrameResizePosition) {
        switch handle {
        case .top: self = .top
        case .leading: self = .leading
        case .bottom: self = .bottom
        case .trailing: self = .trailing
        case .topLeading: self = [.top, .leading]
        case .topTrailing: self = [.top, .trailing]
        case .bottomLeading: self = [.bottom, .leading]
        case .bottomTrailing: self = [.bottom, .trailing]
        }
    }
}

/// A thread's conversation in its popover, above the field (D 2.7): the
/// sidebar's `Conversation`, in the order written, the newest at the
/// foot. One message style in both places, and both read the same thread,
/// so a message written in either shows in both.
struct PopoverConversation: View {
    let model: WindowModel
    let thread: ReviewThread
    /// Whether the conversation takes the room the popover has, in a
    /// popover the person sized; else it grows from `conversationLeast` to
    /// `conversationHeight`.
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
        .frame(
            minHeight: fills ? nil : ThreadPopover.conversationLeast,
            maxHeight: fills ? .infinity : min(max(contentHeight, ThreadPopover.conversationLeast), ThreadPopover.conversationHeight)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Thread \(thread.number)")
    }
}
