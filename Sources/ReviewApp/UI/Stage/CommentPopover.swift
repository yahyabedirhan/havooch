import ReviewCore
import ReviewWire
import SwiftUI

/// The comment popover, for a new message and for a thread alike: one component
/// for a new message and for an existing thread (D 2.7, D 2.9). For a
/// message on a moment it floats at the foot of the stage, above the
/// playhead, with a notch that points at the moment. For a message on a
/// region it sits beside the rectangle, with no notch. Its header names the
/// thread it writes to and the frame's time as the bar shows it; the
/// thread's conversation shows above the field. Each edge and each corner
/// resizes it, as a window's do (L70): on a thread the conversation takes
/// the height, on a new message the field does, and a notch stays on the
/// bottom edge. On a thread the header drags it, and the thread keeps
/// where it was left (D 2.8, D 2.10; `ThreadPopover`).
///
/// Return and Queue queue the words, or answer an open question at once
/// (L14), and the popover stays on its thread; the × and Escape drop them.
/// A click outside and a change of the moment close it through
/// `WindowModel.closePopover`, which owns the rules.
struct CommentPopover: View {
    let model: WindowModel
    let draft: WindowModel.Draft
    /// Where the notch points, from the box's leading edge; nil for a box
    /// beside a region.
    let notch: CGFloat?
    /// The thread it writes to, whose conversation shows above the field
    /// (D 2.7, D 2.9); nil for a popover that starts a thread.
    var thread: ReviewThread? = nil
    /// The size the person gave the box, without its notch (D 2.8); nil
    /// for its own size.
    var size: CGSize? = nil
    /// A drag on the header: its translation, and whether it ended. Nil
    /// for a popover that can't move: one with no thread to keep it.
    var move: ((CGSize, Bool) -> Void)? = nil
    /// A drag on an edge or a corner: which one, then as `move`. Nil for a
    /// popover that can't be resized.
    var resize: ((FrameResizePosition, CGSize, Bool) -> Void)? = nil

    static let width: CGFloat = 340
    static let notchHeight: CGFloat = 7
    /// The space inside the box's edge, kept small around a small field
    /// (D 1.8).
    static let padding: CGFloat = 8
    /// A new message's field: its height at the popover's own size, which
    /// opens the popover at its minimum size, and the least it takes in a
    /// popover the person sized.
    static let fieldHeight: CGFloat = 94
    static let minimumFieldHeight: CGFloat = 34
    /// A thread's field, whatever the popover's size: the conversation
    /// takes the height.
    static let threadFieldHeight: CGFloat = 58
    /// The size rules of a popover for a new message (L70): the header, a
    /// roomy field and the band with its split button always show.
    static let rules = ResizeRules(minimum: CGSize(width: 340, height: 170), maximum: CGSize(width: 560, height: 320))
    /// The closest the notch comes to a side: past the rounded corner.
    static let notchInset: CGFloat = 22
    @Environment(\.palette) private var palette

    /// How tall the field is, least and most: on a thread, always its own
    /// height; on a new message, its own height, or the height the
    /// popover has once the person sized it.
    private var fieldRange: (min: CGFloat, max: CGFloat) {
        if thread != nil { return (Self.threadFieldHeight, Self.threadFieldHeight) }
        return size == nil ? (Self.fieldHeight, Self.fieldHeight) : (Self.minimumFieldHeight, .infinity)
    }

    /// Whether the field answers the agent's open question (L14).
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
            // 10 pt from the field to the band.
            .padding(.bottom, 10)
            footer
                .padding(.horizontal, Self.padding)
                .padding(.vertical, 6)
                // The band runs on into the notch.
                .padding(.bottom, notch == nil ? 0 : Self.notchHeight)
                .background { FooterBand() }
        }
        .frame(width: size?.width ?? Self.width, height: size.map { $0.height + (notch == nil ? 0 : Self.notchHeight) })
        // The band's lower corners and the notch follow the box's outline.
        .clipShape(Bubble(notch: notch, notchHeight: Self.notchHeight))
        .overlay {
            if let resize {
                ResizeEdges(rules: thread == nil ? Self.rules : ThreadPopover.rules, resize: resize)
                    // On the box's outline, above the notch.
                    .padding(.bottom, notch == nil ? 0 : Self.notchHeight)
            }
        }
        .popoverChrome(Bubble(notch: notch, notchHeight: Self.notchHeight), surface: palette.surface(.popover), border: palette[.popoverBorder])
        .accessibilityElement(children: .contain)
        .accessibilityLabel(thread.map { "Thread \($0.number)" } ?? (draft.region == nil ? "New message" : "New message on a region"))
    }

    /// The toolbar band's row: the key hints on the left, and on the right
    /// one `SplitButton`, Queue (or Answer) with an arrow holding Send Now
    /// and Discard. Each runs what its key runs: Return through the field,
    /// Cmd+Return and Escape through the player's keys, so no item binds
    /// Return or a bare Escape, which a text input method needs mid-word.
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
                    // Shown in the menu; the player's keys take Cmd+Return first.
                    .keyboardShortcut(.return, modifiers: .command)
                    // An answer goes at once, so there's nothing to send now.
                    .disabled(answers || !model.canSend)
                Divider()
                Button("Discard") { model.closePopover(.discard) }
            }
            .pressedByKeys(in: model)
        }
    }

    /// `#3 · 0:12`, the kind of message before it and the × after it.
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
            // As the bar shows the time: whole seconds (D 1.7).
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
            .pressedByKeys(in: model) { model.closePopover(.discard) }
            .help("Discard (Esc)")
            .accessibilityLabel("Discard")
        }
        .font(.callout)
        // The header is the handle the popover is dragged by.
        .contentShape(Rectangle())
        .gesture(Self.drag(move ?? { _, _ in }), isEnabled: move != nil)
        .pointerStyle(move == nil ? nil : .grabIdle)
    }

    private var placeholder: String {
        if answers { return "Answer the question…" }
        return thread == nil ? "Add a message…" : "Add a follow-up…"
    }

    /// A drag in the window's coordinates, so the popover moving under the
    /// pointer doesn't change the translation.
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

    /// Where the playhead is across the stage for a message at `fraction`
    /// of the video: on the player bar's track at `track`, with the stage at
    /// `stage`, both in the window's coordinates. Before the track is laid
    /// out, the stage's width stands for it.
    static func playhead(fraction: Double, track: CGRect, stage: CGRect) -> CGFloat {
        let along = CGFloat(min(max(fraction, 0), 1))
        guard track.width > 0 else { return stage.width * along }
        return track.minX + track.width * along - stage.minX
    }

    /// Where the box sits on a stage `stageWidth` wide for a message whose
    /// playhead is at `playhead` across the stage: its leading edge, and
    /// the notch from that edge. The box stays inside the stage; the notch
    /// stays on the playhead as far as the box's corners allow.
    static func placement(playhead: CGFloat, stageWidth: CGFloat) -> (leading: CGFloat, notch: CGFloat) {
        let margin: CGFloat = 10
        let leading = min(max(playhead - width / 2, margin), max(stageWidth - width - margin, margin))
        return (leading, min(max(playhead - leading, notchInset), width - notchInset))
    }

    /// The space between the box and the rectangle it's beside, and
    /// between the box and the stage's edge.
    static let gap: CGFloat = 12

    /// Where a box `box` in size sits for a message on the rectangle
    /// `rect`, on a stage `stage` in size: its top-left corner. It's to the
    /// right of the rectangle, else to its left, else below it, else above
    /// it, and always inside the stage. Over a rectangle that leaves no
    /// room on any side, it sits in the stage's lower right corner.
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

/// The dotted key hints: `↩ queue · ⌘↩ send · esc discard`.
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

/// A key and what it does: the key a step darker than its word, both
/// small, so the hints are there to be found, not read (D 1.7).
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

/// The footer's toolbar band: the `well`, laid twice so it reads on a light
/// popover too, edge to edge under a hairline.
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

/// The popover's edges and corners: eight bands on its outline, centred
/// on it, that resize it as a window's do (L70). Each shows the resize
/// pointer of its edge or corner, with the ways `rules` lets it still go;
/// a drag on an edge moves that edge, and a drag on a corner its two
/// edges. They lie clear of the header, the field and the band.
private struct ResizeEdges: View {
    let rules: ResizeRules
    let resize: (FrameResizePosition, CGSize, Bool) -> Void

    /// How thick an edge's band is, across the outline.
    static let edge: CGFloat = 6
    /// The side of a corner's square.
    static let corner: CGFloat = 12

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                // The corners come last, so they lie above the edges' ends.
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

    /// The band of `handle` on a box `size` in size, centred on its outline.
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

/// A rounded box with a notch on its lower edge.
extension View {
    /// The surface the popover and the notices share: the palette's
    /// `surface` in `shape` (a painted colour, or a material under the
    /// window colour in a native theme), its border and the theme's shadow.
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
    /// Where the notch points; nil for a box with none.
    let notch: CGFloat?
    let notchHeight: CGFloat

    func path(in rect: CGRect) -> Path {
        guard let notch else { return Path(roundedRect: rect, cornerRadius: 10, style: .continuous) }
        let box = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height - notchHeight)
        let x = rect.minX + notch
        var pointer = Path()
        // From just inside the box, so the two join into one outline.
        pointer.move(to: CGPoint(x: x - notchHeight, y: box.maxY - 1))
        pointer.addLine(to: CGPoint(x: x - notchHeight, y: box.maxY))
        pointer.addLine(to: CGPoint(x: x, y: rect.maxY))
        pointer.addLine(to: CGPoint(x: x + notchHeight, y: box.maxY))
        pointer.addLine(to: CGPoint(x: x + notchHeight, y: box.maxY - 1))
        pointer.closeSubpath()
        return Path(roundedRect: box, cornerRadius: 10, style: .continuous).union(pointer)
    }
}
