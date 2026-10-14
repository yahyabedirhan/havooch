import ReviewCore
import ReviewWire
import SwiftUI

struct FrameMarks: View {
    let model: WindowModel
    let geometry: VideoFrameGeometry
    var side: CompareSide?

    static let badgeSize: CGFloat = 20
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

    private func anchor(of mark: WindowModel.FrameMark, index: Int, in marks: [WindowModel.FrameMark]) -> CGPoint {
        if let region = mark.regions.first {
            let rect = geometry.rect(of: region)
            return CGPoint(x: rect.minX, y: rect.minY)
        }
        let before = marks[..<index].filter(\.regions.isEmpty).count
        return CGPoint(
            x: geometry.frame.minX + Self.inset + Self.badgeSize / 2 + CGFloat(before) * (Self.badgeSize + 4),
            y: geometry.frame.minY + Self.inset + Self.badgeSize / 2
        )
    }
}

private struct FrameBadge: View {
    let number: Int
    let hasRegion: Bool
    let open: () -> Void
    @Environment(\.palette) private var palette

    var body: some View {
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
