import CoreGraphics
import Foundation
import ImageIO
import ReviewCore
import UniformTypeIdentifiers

/// Where a video's images are under the support folder, and how one is
/// written:
///
///     <support>/videos/<contentHash>/frames/<comment-id>.png
///     <support>/videos/<contentHash>/crops/<comment-id>.png
public struct ImageFiles: Sendable {
    public let support: URL

    public init(support: URL) {
        self.support = support
    }

    /// Why an image wasn't written, as one line.
    public struct Failure: Error, Equatable {
        public var reason: String
    }

    /// The folder of everything kept about the video with `contentHash`.
    public func folder(of contentHash: String) -> URL {
        support.appendingPathComponent("videos", isDirectory: true)
            .appendingPathComponent(contentHash, isDirectory: true)
    }

    /// The keyframe of `comment` on the video with `contentHash`.
    public func keyframe(of comment: ItemID, contentHash: String) -> URL {
        folder(of: contentHash).appendingPathComponent("frames", isDirectory: true)
            .appendingPathComponent("\(comment.text).png")
    }

    /// The crop of `comment`'s region on the video with `contentHash`. Only
    /// a comment on a region has the file.
    public func crop(of comment: ItemID, contentHash: String) -> URL {
        folder(of: contentHash).appendingPathComponent("crops", isDirectory: true)
            .appendingPathComponent("\(comment.text).png")
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
