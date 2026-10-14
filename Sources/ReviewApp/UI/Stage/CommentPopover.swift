import ReviewCore
import ReviewWire
import SwiftUI

struct CommentPopover: View {
    let model: WindowModel
    let draft: WindowModel.Draft
    let notch: CGFloat?
    var thread: ReviewThread? = nil
    var size: CGSize? = nil
    var move: ((CGSize, Bool) -> Void)? = nil
    var resize: ((FrameResizePosition, CGSize, Bool) -> Void)? = nil

    static let width: CGFloat = 340
    static let notchHeight: CGFloat = 7
    static let padding: CGFloat = 8
    static let fieldHeight: CGFloat = 94
    static let minimumFieldHeight: CGFloat = 34
    static let threadFieldHeight: CGFloat = 58
    static let rules = ResizeRules(minimum: CGSize(width: 340, height: 170), maximum: CGSize(width: 560, height: 320))
    static let notchInset: CGFloat = 22
    @Environment(\.palette) private var palette

    private var fieldRange: (min: CGFloat, max: CGFloat) {
        if thread != nil { return (Self.threadFieldHeight, Self.threadFieldHeight) }
        return size == nil ? (Self.fieldHeight, Self.fieldHeight) : (Self.minimumFieldHeight, .infinity)
    }

    private var answers: Bool { thread?.openQuestion != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                header
                if let thread, !thread.messages.isEmpty {
                    PopoverConversation(model: model, thread: thread, fills: size != nil)
                }
                MessageField(
                    text: text, placeholder: placeholder, wellFocus: answers ? .question : .accent,
                    commit: { model.commitDraft() }, cancel: { model.escape() }
                )
                .frame(maxWidth: .infinity, minHeight: fieldRange.min, maxHeight: fieldRange.max)
            }
            .padding([.horizontal, .top], Self.padding)
            .padding(.bottom, 10)
            footer
                .padding(.horizontal, Self.padding)
                .padding(.vertical, 6)
                .padding(.bottom, notch == nil ? 0 : Self.notchHeight)
                .background { FooterBand() }
        }
        .frame(width: size?.width ?? Self.width, height: size.map { $0.height + (notch == nil ? 0 : Self.notchHeight) })
        .clipShape(Bubble(notch: notch, notchHeight: Self.notchHeight))
        .overlay {
            if let resize {
                ResizeEdges(rules: thread == nil ? Self.rules : ThreadPopover.rules, resize: resize)
                    .padding(.bottom, notch == nil ? 0 : Self.notchHeight)
            }
        }
        .popoverChrome(Bubble(notch: notch, notchHeight: Self.notchHeight), surface: palette.surface(.popover), border: palette[.popoverBorder])
        .accessibilityElement(children: .contain)
        .accessibilityLabel(thread.map { "Thread \($0.number)" } ?? (draft.region == nil ? "New message" : "New message on a region"))
    }

    private var footer: some View {
        HStack(spacing: 6) {
            KeyHints(commitWord: answers ? "answer" : "queue")
            Spacer(minLength: 4)
            SplitButton(
                answers ? "Answer" : "Queue",
                help: answers ? "Answer at once (Return). The arrow discards." : "Queue (Return). The arrow sends now or discards.",
                isEnabled: WindowModel.hasWords(draft.text)
            ) {
                model.commitDraft()
            } menu: {
                Button("Send Now") { model.send() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(answers || !model.canSend)
                Divider()
                Button("Discard") { model.closePopover(.discard) }
            }
            .pressedByKeys(in: model)
        }
    }

    private var header: some View {
        HStack(spacing: 5) {
            Image(systemName: draft.region == nil ? "text.bubble" : "rectangle.dashed")
                .foregroundStyle(palette[.accent])
                .accessibilityHidden(true)
            if let number = model.draftThreadNumber {
                Text("#\(number)")
                    .fontWeight(.semibold)
                    .foregroundStyle(palette[.textPrimary])
                Text("·")
                    .foregroundStyle(palette[.textTertiary])
            }
            Text(TimeCode.text(draft.time.rounded(.down)))
                .monospacedDigit()
                .foregroundStyle(palette[.textSecondary])
            Spacer(minLength: 4)
            Button {
                model.closePopover(.discard)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(palette[.textSecondary])
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .pointerStyle(.link)
            .pressedByKeys(in: model) { model.closePopover(.discard) }
            .help("Discard (Esc)")
            .accessibilityLabel("Discard")
        }
        .font(.callout)
        .contentShape(Rectangle())
        .gesture(Self.drag(move ?? { _, _ in }), isEnabled: move != nil)
        .pointerStyle(move == nil ? nil : .grabIdle)
    }

    private var placeholder: String {
        if answers { return "Answer the question…" }
        return thread == nil ? "Add a message…" : "Add a follow-up…"
    }

    fileprivate static func drag(_ report: @escaping (CGSize, Bool) -> Void) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .global)
            .onChanged { report($0.translation, false) }
            .onEnded { report($0.translation, true) }
    }

    private var text: Binding<String> {
        Binding(
            get: { model.draft?.text ?? "" },
            set: { model.draft?.text = $0 }
        )
    }

    static func playhead(fraction: Double, track: CGRect, stage: CGRect) -> CGFloat {
        let along = CGFloat(min(max(fraction, 0), 1))
        guard track.width > 0 else { return stage.width * along }
        return track.minX + track.width * along - stage.minX
    }

    static func placement(playhead: CGFloat, stageWidth: CGFloat) -> (leading: CGFloat, notch: CGFloat) {
        let margin: CGFloat = 10
        let leading = min(max(playhead - width / 2, margin), max(stageWidth - width - margin, margin))
        return (leading, min(max(playhead - leading, notchInset), width - notchInset))
    }

    static let gap: CGFloat = 12

    static func placement(beside rect: CGRect, box: CGSize, stage: CGSize) -> CGPoint {
        let farthest = CGPoint(x: max(stage.width - box.width - gap, gap), y: max(stage.height - box.height - gap, gap))
        let alongside = min(max(rect.minY, gap), farthest.y)
        let under = min(max(rect.minX, gap), farthest.x)
        if rect.maxX + gap <= farthest.x { return CGPoint(x: rect.maxX + gap, y: alongside) }
        if rect.minX - gap - box.width >= gap { return CGPoint(x: rect.minX - gap - box.width, y: alongside) }
        if rect.maxY + gap <= farthest.y { return CGPoint(x: under, y: rect.maxY + gap) }
        if rect.minY - gap - box.height >= gap { return CGPoint(x: under, y: rect.minY - gap - box.height) }
        return farthest
    }
}

private struct KeyHints: View {
    let commitWord: String
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 5) {
            KeyHint(key: "↩", does: commitWord)
            dot
            KeyHint(key: "⌘↩", does: "send")
            dot
            KeyHint(key: "esc", does: "discard")
        }
        .fixedSize()
    }

    private var dot: some View {
        Text("·").font(.caption2).foregroundStyle(palette[.textTertiary])
    }
}

private struct KeyHint: View {
    let key: String
    let does: String
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 3) {
            Text(key).font(.caption2.weight(.medium)).foregroundStyle(palette[.textSecondary])
            Text(does).font(.caption2).foregroundStyle(palette[.textTertiary])
        }
    }
}

private struct FooterBand: View {
    @Environment(\.palette) private var palette

    var body: some View {
        ZStack {
            palette[.well]
            palette[.well]
        }
        .overlay(alignment: .top) { Hairline(axis: .horizontal) }
    }
}

private struct ResizeEdges: View {
    let rules: ResizeRules
    let resize: (FrameResizePosition, CGSize, Bool) -> Void

    static let edge: CGFloat = 6
    static let corner: CGFloat = 12

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                ForEach(FrameResizePosition.allCases, id: \.self) { handle in
                    let rect = Self.rect(of: handle, in: proxy.size)
                    Color.clear
                        .contentShape(Rectangle())
                        .pointerStyle(.frameResize(position: handle, directions: rules.directions(handle, size: proxy.size)))
                        .gesture(CommentPopover.drag { translation, ended in resize(handle, translation, ended) })
                        .frame(width: rect.width, height: rect.height)
                        .offset(x: rect.minX, y: rect.minY)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
        .accessibilityHidden(true)
    }

    static func rect(of handle: FrameResizePosition, in size: CGSize) -> CGRect {
        let (w, h) = (size.width, size.height)
        let along = CGSize(width: max(w - corner, 0), height: max(h - corner, 0))
        switch handle {
        case .top: return CGRect(x: corner / 2, y: -edge / 2, width: along.width, height: edge)
        case .bottom: return CGRect(x: corner / 2, y: h - edge / 2, width: along.width, height: edge)
        case .leading: return CGRect(x: -edge / 2, y: corner / 2, width: edge, height: along.height)
        case .trailing: return CGRect(x: w - edge / 2, y: corner / 2, width: edge, height: along.height)
        case .topLeading: return CGRect(x: -corner / 2, y: -corner / 2, width: corner, height: corner)
        case .topTrailing: return CGRect(x: w - corner / 2, y: -corner / 2, width: corner, height: corner)
        case .bottomLeading: return CGRect(x: -corner / 2, y: h - corner / 2, width: corner, height: corner)
        case .bottomTrailing: return CGRect(x: w - corner / 2, y: h - corner / 2, width: corner, height: corner)
        }
    }
}

extension View {
    func popoverChrome(_ shape: some Shape, surface: Palette.Surface, border: Color, lineWidth: CGFloat = 1) -> some View {
        modifier(PopoverChrome(shape: shape, surface: surface, border: border, lineWidth: lineWidth))
    }
}

private struct PopoverChrome<S: Shape>: ViewModifier {
    let shape: S
    let surface: Palette.Surface
    let border: Color
    let lineWidth: CGFloat
    @Environment(\.palette) private var palette

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    if let material = surface.material { shape.fill(material) }
                    shape.fill(surface.fill)
                }
            }
            .overlay { shape.stroke(border, lineWidth: lineWidth) }
            .shadow(color: palette[.shadow], radius: 14, y: 5)
    }
}

private struct Bubble: Shape {
    let notch: CGFloat?
    let notchHeight: CGFloat

    func path(in rect: CGRect) -> Path {
        guard let notch else { return Path(roundedRect: rect, cornerRadius: 10, style: .continuous) }
        let box = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height - notchHeight)
        let x = rect.minX + notch
        var pointer = Path()
        pointer.move(to: CGPoint(x: x - notchHeight, y: box.maxY - 1))
        pointer.addLine(to: CGPoint(x: x - notchHeight, y: box.maxY))
        pointer.addLine(to: CGPoint(x: x, y: rect.maxY))
        pointer.addLine(to: CGPoint(x: x + notchHeight, y: box.maxY))
        pointer.addLine(to: CGPoint(x: x + notchHeight, y: box.maxY - 1))
        pointer.closeSubpath()
        return Path(roundedRect: box, cornerRadius: 10, style: .continuous).union(pointer)
    }
}
