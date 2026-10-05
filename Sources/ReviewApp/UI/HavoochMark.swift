import AppKit
import SwiftUI

/// The cat mark: the head of Havuç, the app's logo (logo v2,
/// `assets/images/logo/v2-havuc/`), as the vector PDFs `make logo` draws
/// into `Packaging/Logo/`. At 32 points and under it's the small cut, made
/// to read at 16 pixels: no nose, mouth or catchlights. Decoration: the
/// app's name beside it says what it is.
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

/// Loads the cat mark's PDFs: from the app bundle's `Logo` resources
/// (`make bundle` copies `Packaging/Logo/` there), or from the source
/// tree's `Packaging/Logo/` for a build that isn't bundled.
enum HavoochMarkImage {
    /// The largest size, in points, that shows the small cut.
    static let smallCutLimit: CGFloat = 32

    static let folder: URL? = {
        let bundled = Bundle.main.resourceURL?.appendingPathComponent("Logo", isDirectory: true)
        if let bundled, FileManager.default.fileExists(atPath: bundled.path) { return bundled }
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Packaging/Logo", isDirectory: true)
        return FileManager.default.fileExists(atPath: source.path) ? source : nil
    }()

    /// The full mark, or the small cut; nil when the folder lacks the file.
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
