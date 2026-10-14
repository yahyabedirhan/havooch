import SwiftUI

struct SidebarColumn: View {
    let model: WindowModel
    let preferredWidth: CGFloat
    let maximumWidth: CGFloat
    @State private var dragged: CGFloat?
    @State private var dragStart: CGFloat?
    @Environment(\.palette) private var palette

    static func animation(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.35, dampingFraction: 1)
    }

    var body: some View {
        VStack(spacing: 0) {
            SidebarView(model: model)
                .frame(maxHeight: .infinity)
            Composer(model: model)
        }
        .frame(width: width)
        .background(palette[.window])
        .overlay(alignment: .leading) { Hairline(axis: .vertical) }
        .overlay(alignment: .leading) { resizeHandle }
    }

    private var width: CGFloat { min(dragged ?? preferredWidth, maximumWidth) }

    private var resizeHandle: some View {
        Color.clear
            .frame(width: 6)
            .contentShape(Rectangle())
            .pointerStyle(.columnResize)
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { drag in
                        let start = dragStart ?? width
                        dragStart = start
                        let range = Metrics.sidebarWidthRange.lowerBound...maximumWidth
                        dragged = min(max(start - drag.translation.width, range.lowerBound), range.upperBound)
                    }
                    .onEnded { _ in
                        if let dragged { model.keepSidebarWidth(dragged) }
                        dragStart = nil
                        dragged = nil
                    }
            )
            .accessibilityHidden(true)
    }
}
