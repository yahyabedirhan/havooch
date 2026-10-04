import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A picture written as a PNG file: a comment's keyframe, its region's crop,
/// a screenshot of the window.
enum PNGFile {
    /// Why a picture couldn't be written.
    struct Failure: LocalizedError, Equatable {
        var errorDescription: String?
    }

    /// `image` written as a PNG at `file`, replacing what's there.
    static func write(_ image: CGImage, to file: URL) throws(Failure) {
        guard let destination = CGImageDestinationCreateWithURL(file as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw Failure(errorDescription: "couldn't write \(file.path): its folder doesn't exist or can't be written")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw Failure(errorDescription: "couldn't write \(file.path)")
        }
    }
}
