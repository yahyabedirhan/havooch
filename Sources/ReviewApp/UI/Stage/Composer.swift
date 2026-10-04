import ReviewWire
import SwiftUI

/// The comment box. For a comment on a moment it floats at the foot of the
/// stage, above the playhead, with a notch that points at the moment. For a
/// comment on a region it sits beside the rectangle, with no notch.
struct Composer: View {
    let model: AppModel
    let draft: AppModel.Draft
    /// Where the notch points, from the box's leading edge; nil for a box
    /// beside a region.
    let notch: CGFloat?

    static let width: CGFloat = 340
    static let notchHeight: CGFloat = 7

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                Image(systemName: draft.region == nil ? "text.bubble.fill" : "rectangle.dashed")
                    .fontWeight(draft.region == nil ? .regular : .semibold)
                    .foregroundStyle(.tint)
                Text(draft.region == nil ? "Comment at" : "Comment on this region at")
                    .foregroundStyle(.secondary)
                Text(TimeCode.text(draft.time))
                    .monospacedDigit()
                    .fontWeight(.semibold)
                Spacer()
            }
            .font(.callout)
            CommentField(text: text, commit: { model.commitDraft() }, cancel: { model.escape() })
                .frame(height: 66)
            HStack(spacing: 10) {
                KeyHint(key: "↩", does: "queue")
                // Shift+Return, a new line, is the text view's habit and
                // needs no hint; the row has room for three.
                KeyHint(key: "⌘↩", does: "send")
                KeyHint(key: "esc", does: "cancel")
                Spacer()
                Button("Queue") { model.commitDraft() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(!AppModel.hasWords(draft.text))
            }
        }
        .padding(12)
        .padding(.bottom, notch == nil ? 0 : Self.notchHeight)
        .frame(width: Self.width)
        // A solid surface: over a video a material takes the picture's
        // colours, and the words on it stop being readable.
        .background(Color(nsColor: .windowBackgroundColor), in: Bubble(notch: notch, notchHeight: Self.notchHeight))
        .overlay { Bubble(notch: notch, notchHeight: Self.notchHeight).stroke(.white.opacity(0.16), lineWidth: 1) }
        .shadow(color: .black.opacity(0.45), radius: 14, y: 5)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(draft.region == nil ? "New comment" : "New comment on a region")
    }

    private var text: Binding<String> {
        Binding(
            get: { model.draft?.text ?? "" },
            set: { model.draft?.text = $0 }
        )
    }

    /// Where the box sits on a stage `stageWidth` wide for a comment at
    /// `fraction` of the video: its leading edge, and the notch from that
    /// edge. The box stays inside the stage; the notch stays on the
    /// playhead as far as the box's corners allow.
    static func placement(fraction: Double, stageWidth: CGFloat) -> (leading: CGFloat, notch: CGFloat) {
        let margin: CGFloat = 10
        let playhead = Theme.laneInset + (stageWidth - 2 * Theme.laneInset) * min(max(fraction, 0), 1)
        let leading = min(max(playhead - width / 2, margin), max(stageWidth - width - margin, margin))
        let corner: CGFloat = 22
        return (leading, min(max(playhead - leading, corner), width - corner))
    }

    /// The space between the box and the rectangle it's beside, and
    /// between the box and the stage's edge.
    static let gap: CGFloat = 12

    /// Where a box `box` in size sits for a comment on the rectangle
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

/// A key and what it does, under the comment box.
private struct KeyHint: View {
    let key: String
    let does: String

    var body: some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 4)
                .padding(.vertical, 1.5)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            Text(does)
                .font(.caption)
        }
        .foregroundStyle(.secondary)
        .fixedSize()
    }
}

/// A rounded box with a notch on its lower edge.
private struct Bubble: Shape {
    /// Where the notch points; nil for a box with none.
    let notch: CGFloat?
    let notchHeight: CGFloat

    func path(in rect: CGRect) -> Path {
        guard let notch else { return Path(roundedRect: rect, cornerRadius: 12, style: .continuous) }
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
        return Path(roundedRect: box, cornerRadius: 12, style: .continuous).union(pointer)
    }
}
