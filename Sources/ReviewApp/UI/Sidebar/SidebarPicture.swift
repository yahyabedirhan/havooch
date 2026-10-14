import ReviewCore
import ReviewStore
import SwiftUI

struct SidebarPicture: View {
    let file: URL?
    let side: CGFloat
    var corner: CGFloat = 6
    var fills = false
    var shape: CGFloat?
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
        .overlay {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .strokeBorder(palette[.separator], lineWidth: 0.5)
        }
        .task(id: file) { await load() }
        .accessibilityHidden(true)
    }

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
        for _ in 0..<20 {
            if let picture = await Self.picture(of: file, side: Int(side * max(scale, 1))) {
                image = picture
                return
            }
            try? await Task.sleep(for: .milliseconds(100))
            if Task.isCancelled { return }
        }
    }

    @concurrent
    nonisolated private static func picture(of file: URL, side: Int) async -> CGImage? {
        ImageFiles.thumbnail(of: file, side: side)
    }
}
