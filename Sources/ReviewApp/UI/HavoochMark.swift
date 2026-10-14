import AppKit
import SwiftUI

struct HavoochMark: View {
    let size: CGFloat

    var body: some View {
        Group {
            if let image = HavoochMarkImage.image(small: size <= HavoochMarkImage.smallCutLimit) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                Color.clear
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

enum HavoochMarkImage {
    static let smallCutLimit: CGFloat = 24

    static let folder: URL? = {
        let bundled = Bundle.main.resourceURL?.appendingPathComponent("Logo", isDirectory: true)
        if let bundled, FileManager.default.fileExists(atPath: bundled.path) { return bundled }
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Packaging/Logo", isDirectory: true)
        return FileManager.default.fileExists(atPath: source.path) ? source : nil
    }()

    static func image(small: Bool) -> NSImage? {
        let name = small ? "havooch-mark-small" : "havooch-mark"
        if let cached = cache[name] { return cached }
        guard let url = folder?.appendingPathComponent(name + ".pdf", isDirectory: false),
              let image = NSImage(contentsOf: url)
        else { return nil }
        cache[name] = image
        return image
    }

    private static var cache: [String: NSImage] = [:]
}
