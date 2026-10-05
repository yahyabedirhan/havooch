import SwiftUI
import VRReview

/// What lies over the frame: the pointer's surface, the rectangle of a
/// region, and the comment box. Dragging on the frame draws a region, as
/// Cmd+Shift+4 does: a crosshair, a live rectangle with its size in the
/// frame's pixels, and the rest of the frame dimmed. Letting go opens the
/// comment box next to the rectangle. A press that doesn't move plays or
/// pauses. Every rectangle is placed through `FrameGeometry` on each
/// layout, so a region stays on the same part of the picture when the
/// window changes size.
struct RegionOverlay: View {
    let model: AppModel
    let video: OpenVideo

    /// The comment box's height as it was last laid out: it grows with its text.
    @State private var boxHeight: CGFloat = 96

    private static let footWidth: CGFloat = 520
    private static let besideWidth: CGFloat = 360
    private static let footMargin: CGFloat = 16

    var body: some View {
        GeometryReader { proxy in
            let geometry = FrameGeometry(frame: video.size, view: proxy.size)
            let draft = model.desk.draft
            ZStack(alignment: .topLeading) {
                surface(geometry)
                if let drawn = model.draw.region(in: geometry) {
                    RegionFrame(rect: geometry.rect(of: drawn), frame: geometry.frameRect, dims: true, label: Self.size(of: drawn, in: video))
                } else if let region = draft?.region {
                    RegionFrame(rect: geometry.rect(of: region), frame: geometry.frameRect, dims: true)
                } else if draft == nil, let region = shownRegion {
                    RegionFrame(rect: geometry.rect(of: region), frame: geometry.frameRect, dims: false)
                }
                if let draft {
                    let width = min(draft.region == nil ? Self.footWidth : Self.besideWidth, max(0, proxy.size.width - 2 * Self.footMargin))
                    let origin = boxOrigin(CGSize(width: width, height: boxHeight), region: draft.region, in: geometry)
                    Composer(model: model, time: draft.time, pointsAtRegion: draft.region != nil)
                        .frame(width: width)
                        .onGeometryChange(for: CGFloat.self, of: \.size.height) { boxHeight = $0 }
                        .offset(x: origin.x, y: origin.y)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
    }

    /// The pointer's surface: the whole view takes the press, and over the
    /// frame the pointer is a crosshair.
    private func surface(_ geometry: FrameGeometry) -> some View {
        let frame = geometry.frameRect
        return ZStack(alignment: .topLeading) {
            Color.clear
            Color.clear
                .contentShape(Rectangle())
                .pointerStyle(.rectSelection)
                .frame(width: frame.width, height: frame.height)
                .offset(x: frame.minX, y: frame.minY)
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { drag in
                    model.beginRegion(at: drag.startLocation)
                    model.dragRegion(to: drag.location)
                }
                .onEnded { drag in
                    model.dragRegion(to: drag.location)
                    model.endRegion(in: geometry)
                }
        )
        .accessibilityLabel("Video frame")
        .accessibilityHint("Drag to comment on a part of the frame")
    }

    /// The region of the comment in focus, while the frame it was drawn on
    /// is the one on screen.
    private var shownRegion: Region? {
        guard let id = model.selection, let comment = try? model.desk.open?.comment(id), let region = comment.region,
              !model.player.playing, abs(model.player.time - comment.time) < 0.5 / video.frameRate
        else { return nil }
        return region
    }

    /// Where the comment box goes: next to its region, or centred over the
    /// frame's foot without one.
    private func boxOrigin(_ size: CGSize, region: Region?, in geometry: FrameGeometry) -> CGPoint {
        if let region { return geometry.origin(ofBox: size, beside: geometry.rect(of: region)) }
        return CGPoint(
            x: (geometry.view.width - size.width) / 2,
            y: max(Self.footMargin, geometry.view.height - size.height - Self.footMargin)
        )
    }

    /// `412 × 130`: the region's size in the frame's pixels.
    private static func size(of region: Region, in video: OpenVideo) -> String {
        let pixels = region.pixels(in: (Int(video.size.width.rounded()), Int(video.size.height.rounded())))
        return "\(pixels.width) × \(pixels.height)"
    }
}

/// A region's rectangle over the frame. With `dims`, the rest of the frame
/// is darkened, as while a region is drawn or commented on.
private struct RegionFrame: View {
    let rect: CGRect
    let frame: CGRect
    let dims: Bool
    var label: String?

    var body: some View {
        ZStack(alignment: .topLeading) {
            if dims {
                Path { path in
                    path.addRect(frame)
                    path.addRect(rect)
                }
                .fill(Color.black.opacity(0.35), style: FillStyle(eoFill: true))
            }
            // Dark under light, so the edge reads on any picture.
            Path(rect.insetBy(dx: -1, dy: -1)).stroke(Color.black.opacity(0.35), lineWidth: 1)
            Path(rect).stroke(dims ? Color.white : Color.accentColor, lineWidth: dims ? 1.5 : 2)
            if let label {
                Text(label)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 4))
                    .fixedSize()
                    .offset(x: rect.minX, y: rect.maxY + 6)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
