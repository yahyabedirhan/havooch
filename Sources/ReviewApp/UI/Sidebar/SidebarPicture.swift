import ReviewCore
import ReviewStore
import SwiftUI

/// A picture of the sidebar: a keyframe or a crop, read from its file off
/// the main actor and made only as large as it shows. The letterbox fills
/// the place until the picture is there, and where there is none.
struct SidebarPicture: View {
    /// The PNG to show; nil shows the letterbox only.
    let file: URL?
    /// The longest side the picture is shown at, in points.
    let side: CGFloat
    var corner: CGFloat = 6
    /// Whether the picture fills its frame and is cut (a thumbnail), or
    /// shows whole inside it (a keyframe or a crop).
    var fills = false
    /// The shape the picture takes until it is read; nil keeps the frame
    /// it's given. Once read, the picture takes its own shape.
    var shape: CGFloat?
    /// The regions outlined on the picture, where they are on its frame:
    /// a thread's on its keyframe. Only a picture shown whole has them.
    var regions: [Region] = []

    @State private var image: CGImage?
    @Environment(\.palette) private var palette
    @Environment(\.displayScale) private var scale

    var body: some View {
        if let shape {
            picture.aspectRatio(image.map(Self.aspect) ?? shape, contentMode: .fit)
        } else {
            picture
        }
    }

    private var picture: some View {
        ZStack {
            palette[.letterbox]
            if let image {
                Image(decorative: image, scale: scale)
                    .resizable()
                    .aspectRatio(contentMode: fills ? .fill : .fit)
                if !fills, !regions.isEmpty {
                    outlines(aspect: Self.aspect(of: image))
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        // A hairline only, so the letterbox keeps an edge on a dark sidebar.
        .overlay {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .strokeBorder(palette[.separator], lineWidth: 0.5)
        }
        .task(id: file) { await load() }
        .accessibilityHidden(true)
    }

    /// The regions' outlines on the picture shown whole at `aspect` in the
    /// middle of the frame.
    private func outlines(aspect: CGFloat) -> some View {
        GeometryReader { proxy in
            let size = proxy.size
            let fitted = size.width / max(size.height, 1) > aspect
                ? CGSize(width: size.height * aspect, height: size.height)
                : CGSize(width: size.width, height: size.width / aspect)
            let origin = CGPoint(x: (size.width - fitted.width) / 2, y: (size.height - fitted.height) / 2)
            ForEach(Array(regions.enumerated()), id: \.offset) { _, region in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .strokeBorder(palette[.regionOutline], lineWidth: 1.5)
                    .frame(width: max(fitted.width * region.w, 3), height: max(fitted.height * region.h, 3))
                    .offset(x: origin.x + fitted.width * region.x, y: origin.y + fitted.height * region.y)
            }
        }
    }

    private static func aspect(of image: CGImage) -> CGFloat {
        image.height > 0 ? CGFloat(image.width) / CGFloat(image.height) : 16 / 9
    }

    private func load() async {
        guard let file else {
            image = nil
            return
        }
        // A message shows a moment before its crop is moved into place.
        for _ in 0..<20 {
            if let picture = await Self.picture(of: file, side: Int(side * max(scale, 1))) {
                image = picture
                return
            }
            try? await Task.sleep(for: .milliseconds(100))
            if Task.isCancelled { return }
        }
    }

    /// The picture at `file`, made small off the main actor.
    @concurrent
    nonisolated private static func picture(of file: URL, side: Int) async -> CGImage? {
        ImageFiles.thumbnail(of: file, side: side)
    }
}
