import ReviewCore
import ReviewWire
import SwiftUI

struct RegionOverlay: View {
    let model: WindowModel
    let geometry: VideoFrameGeometry
    let engine: PlayerEngine
    var side: CompareSide?
    var hitWidth: CGFloat?

    private struct Drag: Equatable {
        var start: CGPoint
        var current: CGPoint
    }

    @State private var drag: Drag?

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
                .contentShape(LeadingPart(width: hitWidth))
                .gesture(draw)
            if let shown = drawn {
                RegionFrame(rect: shown.rect, within: geometry.frame, label: shown.label)
                    .transition(.opacity)
            }
        }
        .animation(.smooth(duration: 0.15), value: model.draft?.region)
    }

    private var drawn: (rect: CGRect, label: String?)? {
        guard side == nil || side == model.activeSide else { return nil }
        if let drag, model.isDrawingRegion {
            let rect = geometry.rect(from: drag.start, to: drag.current)
            return (rect, Self.size(of: rect, within: geometry.frame, video: engine.videoSize))
        }
        guard let region = model.draft?.region ?? (model.draft == nil ? model.composerRegion : nil) else { return nil }
        return (geometry.rect(of: region), nil)
    }

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
                    model.beginRegion(on: side)
                }
                drag = Drag(start: value.startLocation, current: value.location)
            }
            .onEnded { value in
                if drag == nil {
                    model.clickFrame(on: side)
                } else {
                    model.endRegion(geometry.region(from: value.startLocation, to: value.location))
                }
                drag = nil
            }
    }
}

private struct LeadingPart: Shape {
    var width: CGFloat?

    func path(in rect: CGRect) -> Path {
        Path(CGRect(x: rect.minX, y: rect.minY, width: min(rect.width, max(width ?? rect.width, 0)), height: rect.height))
    }
}

private struct RegionFrame: View {
    let rect: CGRect
    let within: CGRect
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
                    .offset(x: rect.minX, y: rect.maxY + 6)
            }
        }
        .allowsHitTesting(false)
        .accessibilityElement()
        .accessibilityLabel(label.map { "Region of the new message, \($0) pixels" } ?? "Region of the new message")
    }
}

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
