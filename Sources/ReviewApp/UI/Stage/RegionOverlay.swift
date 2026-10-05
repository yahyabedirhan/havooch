import ReviewCore
import SwiftUI

/// The layer above the picture that takes the mouse. A click plays or
/// pauses. A drag draws a rectangle, as Cmd+Shift+4 does, with no drawing
/// mode: the video pauses, and letting go opens the comment box beside the
/// rectangle. The layer also shows the region of the comment being written
/// and of the selected comment.
struct RegionOverlay: View {
    let model: AppModel
    let geometry: VideoFrameGeometry

    /// The drag under way, in the stage's points.
    private struct Drag: Equatable {
        var start: CGPoint
        var current: CGPoint
    }

    /// Set once the pointer has moved far enough to be a drag.
    @State private var drag: Drag?

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
                .contentShape(Rectangle())
                .gesture(draw)
            // One frame for the rectangle being drawn and the region shown,
            // so letting go hands the rectangle to the comment box in place
            // instead of fading one frame out and another in.
            if let shown = drawn {
                RegionFrame(rect: shown.rect, within: geometry.frame, isDraft: shown.isDraft, pin: shown.pin)
                    .transition(.opacity)
            }
        }
        // Only a change of the shown region animates; the rectangle being
        // drawn follows the pointer as it moves.
        .animation(.smooth(duration: 0.15), value: model.shownRegion)
    }

    /// The rectangle to draw: the one being drawn, else the shown region.
    private var drawn: (rect: CGRect, isDraft: Bool, pin: (number: Int, state: CommentState)?)? {
        if let drag, model.isDrawingRegion {
            return (geometry.rect(from: drag.start, to: drag.current), true, nil)
        }
        guard let shown = model.shownRegion else { return nil }
        return (geometry.rect(of: shown.region), shown.number == nil, shown.number.map { (number: $0, state: shown.state) })
    }

    private var draw: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                if drag == nil {
                    guard VideoFrameGeometry.isDrag(from: value.startLocation, to: value.location) else { return }
                    model.beginRegion()
                }
                drag = Drag(start: value.startLocation, current: value.location)
            }
            .onEnded { value in
                if drag == nil {
                    model.clickFrame()
                } else {
                    // After Escape the model no longer draws, and this opens nothing.
                    model.endRegion(geometry.region(from: value.startLocation, to: value.location))
                }
                drag = nil
            }
    }
}

/// A region on the picture: the rest of the picture dimmed, the rectangle
/// outlined in the accent colour, and the comment's pin on its corner.
private struct RegionFrame: View {
    let rect: CGRect
    /// The picture: only it is dimmed, not the letterbox.
    let within: CGRect
    /// A rectangle being drawn or written about dims the picture more than
    /// a queued comment's, which is there to be looked at.
    let isDraft: Bool
    var pin: (number: Int, state: CommentState)?

    var body: some View {
        ZStack(alignment: .topLeading) {
            Path { path in
                path.addRect(within)
                path.addRect(rect)
            }
            .fill(.black.opacity(isDraft ? 0.5 : 0.38), style: FillStyle(eoFill: true))
            Rectangle()
                .strokeBorder(.black.opacity(0.45), lineWidth: 1)
                .frame(width: rect.width + 6, height: rect.height + 6)
                .offset(x: rect.minX - 3, y: rect.minY - 3)
            Rectangle()
                .strokeBorder(.tint, lineWidth: 2)
                .frame(width: rect.width + 4, height: rect.height + 4)
                .offset(x: rect.minX - 2, y: rect.minY - 2)
            if let pin {
                MarkerPin(number: pin.number, state: pin.state, isSelected: true)
                    .offset(x: rect.minX - MarkerPin.size / 2, y: rect.minY - MarkerPin.size / 2)
            }
        }
        .allowsHitTesting(false)
        .accessibilityElement()
        .accessibilityLabel(pin.map { "Region of comment \($0.number)" } ?? "Region of the new comment")
    }
}
