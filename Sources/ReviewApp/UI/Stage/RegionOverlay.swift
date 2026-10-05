import ReviewCore
import SwiftUI

/// The layer above the picture that takes the mouse. A click plays or
/// pauses, or closes an open popover as a click outside it. A drag draws a
/// rectangle, as Cmd+Shift+4 does, with no drawing mode: the video pauses,
/// the rectangle shows its size in the frame's pixels while it's drawn
/// (D 2.4), and letting go opens the popover beside it. The layer
/// also shows the region of the message in the popover, else the region
/// chip of the composer at the sidebar's foot (L41).
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
            // One frame for the rectangle being drawn and the popover's
            // region, so letting go hands the rectangle to the popover in
            // place instead of fading one frame out and another in.
            if let shown = drawn {
                RegionFrame(rect: shown.rect, within: geometry.frame, label: shown.label)
                    .transition(.opacity)
            }
        }
        // Only a change of the popover's region animates; the rectangle
        // being drawn follows the pointer as it moves.
        .animation(.smooth(duration: 0.15), value: model.draft?.region)
    }

    /// The rectangle to draw: the one being drawn, with its size, else the
    /// region of the message in the popover.
    private var drawn: (rect: CGRect, label: String?)? {
        if let drag, model.isDrawingRegion {
            let rect = geometry.rect(from: drag.start, to: drag.current)
            return (rect, Self.size(of: rect, within: geometry.frame, video: model.engine.videoSize))
        }
        // With no popover open, the composer's region chip (L41).
        guard let region = model.draft?.region ?? (model.draft == nil ? model.composerRegion : nil) else { return nil }
        return (geometry.rect(of: region), nil)
    }

    /// `412 × 236`: the rectangle `rect` on a picture shown at `frame`, in
    /// the pixels of a video `video` in size, as the crop will be.
    static func size(of rect: CGRect, within frame: CGRect, video: CGSize) -> String? {
        guard frame.width > 0, frame.height > 0, video.width > 0, video.height > 0 else { return nil }
        let width = Int((rect.width / frame.width * video.width).rounded())
        let height = Int((rect.height / frame.height * video.height).rounded())
        return "\(width) × \(height)"
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

/// The region being drawn or written about: the rest of the picture
/// dimmed, the rectangle outlined, and while it's drawn its size under it.
private struct RegionFrame: View {
    let rect: CGRect
    /// The picture: only it is dimmed, not the letterbox.
    let within: CGRect
    /// The rectangle's size in the frame's pixels, while it's drawn.
    let label: String?
    @Environment(\.palette) private var palette

    var body: some View {
        ZStack(alignment: .topLeading) {
            Path { path in
                path.addRect(within)
                path.addRect(rect)
            }
            .fill(palette[.regionDim], style: FillStyle(eoFill: true))
            RegionOutline(rect: rect)
            if let label {
                Text(label)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(palette[.sizeLabel])
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(palette[.regionDim], in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .fixedSize()
                    // Under the rectangle's lower left corner, where the pointer isn't.
                    .offset(x: rect.minX, y: rect.maxY + 6)
            }
        }
        .allowsHitTesting(false)
        .accessibilityElement()
        .accessibilityLabel(label.map { "Region of the new message, \($0) pixels" } ?? "Region of the new message")
    }
}

/// A region's outline: the outline colour over a thin shadow line, so the
/// edge reads on any picture.
struct RegionOutline: View {
    let rect: CGRect
    @Environment(\.palette) private var palette

    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .strokeBorder(palette[.shadow], lineWidth: 1)
                .frame(width: rect.width + 6, height: rect.height + 6)
                .offset(x: rect.minX - 3, y: rect.minY - 3)
            Rectangle()
                .strokeBorder(palette[.regionOutline], lineWidth: 2)
                .frame(width: rect.width + 4, height: rect.height + 4)
                .offset(x: rect.minX - 2, y: rect.minY - 2)
        }
        .allowsHitTesting(false)
    }
}
