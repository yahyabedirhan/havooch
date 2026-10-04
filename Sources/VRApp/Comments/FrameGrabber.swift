import AVFoundation
import ImageIO
import UniformTypeIdentifiers

/// Why a frame wasn't read or written, as one line.
struct FrameFailure: Error, Equatable {
    var why: String
}

/// A video's frames as images and PNG files, read from the video's file and
/// never from the screen: a keyframe is the exact frame at its time, at the
/// video's own size, whatever the window shows.
enum FrameGrabber {
    /// The frame `video` shows at `seconds`, upright. At the video's very
    /// end, where no frame starts, it's the last one.
    static func frame(of video: URL, at seconds: Double) async throws(FrameFailure) -> CGImage {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: video))
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let time = CMTime(seconds: seconds, preferredTimescale: 60_000)
        do {
            return try await generator.image(at: time).image
        } catch {
            // Past the last frame's start an exact read finds nothing: take the frame before.
            generator.requestedTimeToleranceBefore = CMTime(value: 1, timescale: 1)
            do {
                return try await generator.image(at: time).image
            } catch {
                throw FrameFailure(why: error.localizedDescription)
            }
        }
    }

    /// `image` written as a PNG at `file`, replacing what's there; the
    /// folders above it are made when missing.
    static func write(_ image: CGImage, to file: URL) throws(FrameFailure) {
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        } catch {
            throw FrameFailure(why: error.localizedDescription)
        }
        guard let destination = CGImageDestinationCreateWithURL(file as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw FrameFailure(why: "\(file.path) can't be written")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw FrameFailure(why: "\(file.path) can't be written")
        }
    }
}
