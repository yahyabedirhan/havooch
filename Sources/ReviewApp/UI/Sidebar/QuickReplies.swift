import ReviewCore
import SwiftUI

struct QuickReplies: View {
    let model: WindowModel
    let thread: ThreadID
    let choices: [String]
    @Environment(\.palette) private var palette

    static func choices(of thread: ReviewThread, isPointingAtRegion: Bool) -> [String] {
        guard !isPointingAtRegion else { return [] }
        return thread.openQuestion?.choices ?? []
    }

    var body: some View {
        ChipFlow(spacing: 6) {
            Text("Quick reply")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(palette[.textTertiary])
                .frame(height: QuickReplyChip.height)
                .accessibilityHidden(true)
            ForEach(Array(choices.enumerated()), id: \.offset) { index, choice in
                QuickReplyChip(model: model, title: choice) { model.chooseAnswer(thread, choice: index + 1) }
            }
        }
        .padding(.leading, MessageBubble.avatar + 8)
        .padding(.trailing, MessageBubble.agentInset)
        .padding(.top, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Quick replies")
    }
}

private struct QuickReplyChip: View {
    let model: WindowModel
    let title: String
    let action: () -> Void
    @State private var isHovered = false
    @Environment(\.palette) private var palette

    static let height: CGFloat = 26

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.callout.weight(.medium))
                .foregroundStyle(palette[.question])
                .lineLimit(1)
                .padding(.horizontal, 11)
                .frame(height: Self.height)
                .background(palette[.question].opacity(isHovered ? 0.22 : 0.12), in: Capsule())
                .overlay { Capsule().strokeBorder(palette[.question].opacity(0.45), lineWidth: 1) }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .pressedByKeys(in: model, action: action)
        .onHover { isHovered = $0 }
        .animation(.smooth(duration: 0.12), value: isHovered)
        .help("Answer “\(title)” at once")
        .accessibilityLabel("Answer: \(title)")
    }
}

private struct ChipFlow: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(in: proposal.width ?? .infinity, subviews)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(in: bounds.width, subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                let width = min(size.width, bounds.width)
                subviews[index].place(
                    at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: ProposedViewSize(width: width, height: size.height)
                )
                x += width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func rows(in width: CGFloat, _ subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let fitted = min(size.width, width)
            if !row.indices.isEmpty, row.width + spacing + fitted > width {
                rows.append(row)
                row = Row()
            }
            row.width += (row.indices.isEmpty ? 0 : spacing) + fitted
            row.height = max(row.height, size.height)
            row.indices.append(index)
        }
        if !row.indices.isEmpty { rows.append(row) }
        return rows
    }
}
