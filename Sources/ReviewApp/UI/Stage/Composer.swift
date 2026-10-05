import ReviewCore
import ReviewWire
import SwiftUI

/// The popover, for a new message and for a thread alike: one component
/// for a new message and for an existing thread (D 2.7, D 2.9). For a
/// message on a moment it floats at the foot of the stage, above the
/// playhead, with a notch that points at the moment. For a message on a
/// region it sits beside the rectangle, with no notch. Its header names the
/// thread it writes to and the frame's time as the bar shows it; the
/// thread's conversation shows above the field. On a thread, the header
/// drags it and the corner grip resizes it, and the thread keeps where it
/// was left (D 2.8, D 2.10; `ThreadPopover`).
///
/// Return and Queue queue the words, or answer an open question at once
/// (L14), and the popover stays on its thread; the × and Escape drop them.
/// A click outside and a change of the moment close it through
/// `AppModel.closePopover`, which owns the rules.
struct Composer: View {
    let model: AppModel
    let draft: AppModel.Draft
    /// Where the notch points, from the box's leading edge; nil for a box
    /// beside a region.
    let notch: CGFloat?
    /// The thread it writes to, whose conversation shows above the field
    /// (D 2.7, D 2.9); nil for a popover that starts a thread.
    var thread: ReviewThread? = nil
    /// The size the person gave it (D 2.8); nil for its own size.
    var size: CGSize? = nil
    /// A drag on the header: its translation, and whether it ended. Nil
    /// for a popover that can't move: one with no thread to keep it.
    var move: ((CGSize, Bool) -> Void)? = nil
    /// A drag on the corner grip, as `move`.
    var resize: ((CGSize, Bool) -> Void)? = nil

    static let width: CGFloat = 320
    static let notchHeight: CGFloat = 7
    /// The space inside the box's edge, kept small around a small field
    /// (D 1.8).
    static let padding: CGFloat = 8
    @Environment(\.palette) private var palette

    /// Whether the field answers the agent's open question (L14).
    private var answers: Bool { thread?.openQuestion != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            if let thread, !thread.messages.isEmpty {
                PopoverConversation(model: model, thread: thread, fills: size != nil)
            }
            MessageField(text: text, placeholder: placeholder, commit: { model.commitDraft() }, cancel: { model.escape() })
                .frame(maxWidth: .infinity, minHeight: 58, maxHeight: 58)
            HStack(spacing: 8) {
                KeyHint(key: "↩", does: answers ? "answer" : "queue")
                KeyHint(key: "⌘↩", does: "send")
                KeyHint(key: "esc", does: "discard")
                Spacer(minLength: 4)
                Button(answers ? "Answer" : "Queue") { model.commitDraft() }
                    .buttonStyle(.borderedProminent)
                    .tint(answers ? palette[.question] : palette[.accent])
                    .controlSize(.mini)
                    .disabled(!AppModel.hasWords(draft.text))
                if resize != nil {
                    // Room for the grip in the corner.
                    Spacer().frame(width: 6)
                }
            }
        }
        .padding(Self.padding)
        .padding(.bottom, notch == nil ? 0 : Self.notchHeight)
        .frame(width: size?.width ?? Self.width, height: size?.height)
        .overlay(alignment: .bottomTrailing) {
            if let resize {
                ResizeGrip()
                    .padding(2)
                    .gesture(Self.drag(resize))
            }
        }
        .popoverChrome(Bubble(notch: notch, notchHeight: Self.notchHeight), surface: palette.surface(.popover), border: palette[.popoverBorder])
        .accessibilityElement(children: .contain)
        .accessibilityLabel(thread.map { "Thread \($0.number)" } ?? (draft.region == nil ? "New message" : "New message on a region"))
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
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(QuietButtonStyle())
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
    private static func drag(_ report: @escaping (CGSize, Bool) -> Void) -> some Gesture {
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
        let corner: CGFloat = 22
        return (leading, min(max(playhead - leading, corner), width - corner))
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

/// A key and what it does, under the field.
private struct KeyHint: View {
    let key: String
    let does: String
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 3) {
            Text(key)
                .font(.caption2.weight(.medium))
            Text(does)
                .font(.caption2)
        }
        // Quiet: the hints are there to be found, not read (D 1.7).
        .foregroundStyle(palette[.textTertiary])
        .fixedSize()
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
