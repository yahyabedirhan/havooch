import ReviewCore
import ReviewWire
import SwiftUI

/// The threads on the frame on screen (D 2.6): each one's region outlines,
/// and one number badge per thread at its first region's top-left corner,
/// or the picture's top-left corner for a thread on the whole frame. A
/// click on a badge opens its thread popover. Nothing opens by itself (D 2.11).
struct FrameMarks: View {
    let model: WindowModel
    let geometry: VideoFrameGeometry
    /// While comparing, the side whose frame it marks; nil for the
    /// window's one video.
    var side: CompareSide?

    static let badgeSize: CGFloat = 20
    /// How far a whole-frame badge sits in from the picture's corner.
    private static let inset: CGFloat = 10

    var body: some View {
        let marks = model.frameMarks(on: side)
        ZStack(alignment: .topLeading) {
            ForEach(marks, id: \.thread) { mark in
                ForEach(Array(mark.regions.enumerated()), id: \.offset) { _, region in
                    RegionOutline(rect: geometry.rect(of: region))
                }
            }
            ForEach(Array(marks.enumerated()), id: \.element.thread) { index, mark in
                let corner = anchor(of: mark, index: index, in: marks)
                FrameBadge(number: mark.number, hasRegion: !mark.regions.isEmpty) { model.openThread(mark.thread) }
                    .offset(x: corner.x - Self.badgeSize / 2, y: corner.y - Self.badgeSize / 2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Where `mark`'s badge is centred: its first region's corner, else the
    /// picture's corner, beside the badges of the threads before it there.
    private func anchor(of mark: WindowModel.FrameMark, index: Int, in marks: [WindowModel.FrameMark]) -> CGPoint {
        if let region = mark.regions.first {
            let rect = geometry.rect(of: region)
            return CGPoint(x: rect.minX, y: rect.minY)
        }
        // On one frame, only one thread can be on the whole frame; the
        // offset only keeps two from covering each other if that changes.
        let before = marks[..<index].filter(\.regions.isEmpty).count
        return CGPoint(
            x: geometry.frame.minX + Self.inset + Self.badgeSize / 2 + CGFloat(before) * (Self.badgeSize + 4),
            y: geometry.frame.minY + Self.inset + Self.badgeSize / 2
        )
    }
}

/// A thread's number on the frame: a rounded square for a thread with a
/// region, a circle for one on the whole frame, as its pin on the bar.
private struct FrameBadge: View {
    let number: Int
    let hasRegion: Bool
    let open: () -> Void
    @Environment(\.palette) private var palette

    var body: some View {
        // Drawn by SwiftUI alone, with no tooltip: a tooltip makes the badge
        // an AppKit view, which the popover's text view then hides.
        Text("\(number)")
            .font(.system(size: number > 99 ? 8.5 : 11, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(palette[.badgeText])
            .frame(width: FrameMarks.badgeSize, height: FrameMarks.badgeSize)
            .background(palette[.badge], in: shape)
            .overlay { shape.strokeBorder(palette[.shadow], lineWidth: 1) }
            .contentShape(shape)
            .onTapGesture(perform: open)
            .accessibilityElement()
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel("Thread \(number)")
            .accessibilityAction { open() }
    }

    private var shape: some InsettableShape {
        RoundedRectangle(cornerRadius: hasRegion ? 5 : FrameMarks.badgeSize / 2, style: .continuous)
    }
}
