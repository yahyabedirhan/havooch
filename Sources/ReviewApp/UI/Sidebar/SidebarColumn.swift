import SwiftUI

/// The sidebar column: the threads and the dock at its foot, resizable from its
/// leading edge between `Metrics.sidebarWidthRange`'s bounds. A hairline
/// on that edge separates it from the stage.
struct SidebarColumn: View {
    let model: WindowModel
    let preferredWidth: CGFloat
    let maximumWidth: CGFloat
    /// The width while the person drags; nil shows the kept width.
    @State private var dragged: CGFloat?
    /// The width when the drag started.
    @State private var dragStart: CGFloat?
    @Environment(\.palette) private var palette

    /// The column's motion: a critically damped spring, so it
    /// settles without a bounce; a short fade when motion is reduced.
    static func animation(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.35, dampingFraction: 1)
    }

    var body: some View {
        VStack(spacing: 0) {
            SidebarView(model: model)
                .frame(maxHeight: .infinity)
            // One dock for the list, the thread view and the Connect view
            // alike: the composer, the presence pill and Send.
            Composer(model: model)
        }
        .frame(width: width)
        .background(palette[.window])
        .overlay(alignment: .leading) { Hairline(axis: .vertical) }
        .overlay(alignment: .leading) { resizeHandle }
    }

    private var width: CGFloat { min(dragged ?? preferredWidth, maximumWidth) }

    /// A thin strip on the leading edge that drags the width. The width is
    /// kept in the settings when the drag ends.
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
