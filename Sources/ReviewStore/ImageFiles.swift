// ImageIO exists on Apple platforms only; elsewhere the module builds without images.
#if canImport(ImageIO)
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// How a video's images are written, removed and read small. Where they
/// are is `SupportLayout`'s (`keyframe`, `crop`).
public enum ImageFiles {
    /// Why an image wasn't written, as one line.
    public struct Failure: Error, Equatable {
        public var reason: String
    }

    /// `image` written as a PNG at `file`, replacing what's there; its
    /// folder is made when it's missing.
    public static func write(_ image: CGImage, to file: URL) throws(Failure) {
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        } catch {
            throw Failure(reason: "couldn't create \(file.deletingLastPathComponent().path): \(error.localizedDescription)")
        }
        guard let destination = CGImageDestinationCreateWithURL(file as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw Failure(reason: "couldn't write \(file.path)")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw Failure(reason: "couldn't write \(file.path)") }
    }

    /// Removes the image at `file`; one that isn't there is fine.
    public static func remove(_ file: URL) {
        try? FileManager.default.removeItem(at: file)
    }

    /// A small copy of the image at `file`, at most `side` pixels on its
    /// longer side, without reading the whole picture into memory.
    public static func thumbnail(of file: URL, side: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(file as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: side,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
#endif
