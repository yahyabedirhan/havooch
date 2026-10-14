import ReviewCore
import SwiftUI

enum ThreadPopover {
    static let minimumSize = CGSize(width: 340, height: 320)
    static let margin: CGFloat = 8
    static let conversationHeight: CGFloat = 200
    static let conversationLeast: CGFloat = 180

    static func rect(of frame: PopoverFrame, in stage: CGSize) -> CGRect {
        fit(
            CGRect(x: frame.x * stage.width, y: frame.y * stage.height, width: frame.w * stage.width, height: frame.h * stage.height),
            in: stage
        )
    }

    static func frame(of rect: CGRect, in stage: CGSize) -> PopoverFrame {
        let fitted = fit(rect, in: stage)
        guard stage.width > 0, stage.height > 0 else { return PopoverFrame(x: 0, y: 0, w: 1, h: 1) }
        return PopoverFrame(
            x: fitted.minX / stage.width, y: fitted.minY / stage.height,
            w: fitted.width / stage.width, h: fitted.height / stage.height
        )
    }

    static func fit(_ rect: CGRect, in stage: CGSize) -> CGRect {
        let room = CGSize(width: max(stage.width - 2 * margin, 0), height: max(stage.height - 2 * margin, 0))
        let width = min(max(rect.width, minimumSize.width), room.width)
        let height = min(max(rect.height, minimumSize.height), room.height)
        let x = min(max(rect.minX, margin), max(stage.width - margin - width, margin))
        let y = min(max(rect.minY, margin), max(stage.height - margin - height, margin))
        return CGRect(x: x, y: y, width: width, height: height)
    }

    static let rules = ResizeRules(minimum: minimumSize, maximum: CGSize(width: 640, height: 560))

    struct Drag: Equatable {
        var handle: FrameResizePosition?
        var start: CGRect
        var translation: CGSize = .zero

        func rect(in stage: CGSize) -> CGRect {
            guard let handle else {
                return fit(start.offsetBy(dx: translation.width, dy: translation.height), in: stage)
            }
            let room = CGRect(origin: .zero, size: stage).insetBy(dx: margin, dy: margin)
            return rules.resized(fit(start, in: stage), from: handle, by: translation, in: room)
        }
    }
}

struct ResizeRules: Equatable {
    let minimum: CGSize
    let maximum: CGSize

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

struct PopoverConversation: View {
    let model: WindowModel
    let thread: ReviewThread
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
