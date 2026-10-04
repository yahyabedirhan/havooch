import AVFoundation
import Foundation
import ImageIO
import UniformTypeIdentifiers
import VRReview

/// What the model asks for a comment's picture: AVFoundation in the app, a
/// fake in tests.
protocol FrameGrabbing: Sendable {
    /// Writes the frame the video shows at `seconds` as a PNG at `file`,
    /// creating its folder, and returns the frame's size in pixels.
    func writeKeyframe(of video: URL, at seconds: Double, to file: URL) async throws -> CGSize
    /// Writes the part of the keyframe at `keyframe` that `region` covers as
    /// a PNG at `file`, creating its folder.
    func writeCrop(of keyframe: URL, region: Region, to file: URL) async throws
}

/// Why a frame couldn't be saved.
struct FrameFailure: LocalizedError {
    var errorDescription: String?
}

/// Frames read from the video file itself, never from the screen, and crops
/// cut from those frames: a comment made in the window and one made from the
/// command line at the same time and region give the same pixels, at any
/// window size.
struct FrameGrabber: FrameGrabbing {
    /// How far before the asked time a frame may be when none is exactly
    /// there: a time at the video's very end, after its last frame.
    private static let endTolerance = CMTime(seconds: 1, preferredTimescale: 600)

    func writeKeyframe(of video: URL, at seconds: Double, to file: URL) async throws -> CGSize {
        let frame = try await Self.frame(of: video, at: seconds)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.write(frame.image, to: file)
        return CGSize(width: frame.image.width, height: frame.image.height)
    }

    func writeCrop(of keyframe: URL, region: Region, to file: URL) async throws {
        guard let source = CGImageSourceCreateWithURL(keyframe as CFURL, nil),
              let frame = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw FrameFailure(errorDescription: "couldn't read \(keyframe.path)")
        }
        // A CGImage's pixels count from its top left, as a region does.
        let pixels = region.pixelRect(in: CGSize(width: frame.width, height: frame.height))
        guard let crop = frame.cropping(to: pixels) else {
            throw FrameFailure(errorDescription: "couldn't cut the region \(region.text) from \(keyframe.path)")
        }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.write(crop, to: file)
    }

    /// The frame shown at `seconds`, at the track's natural size with its
    /// transform applied, and the time that frame starts at.
    static func frame(of video: URL, at seconds: Double) async throws -> (image: CGImage, time: Double) {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: video))
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let time = CMTime(seconds: seconds, preferredTimescale: 60_000)
        do {
            let frame = try await generator.image(at: time)
            return (frame.image, frame.actualTime.seconds)
        } catch {
            generator.requestedTimeToleranceBefore = endTolerance
            let frame = try await generator.image(at: time)
            return (frame.image, frame.actualTime.seconds)
        }
    }

    /// `image` written as a PNG at `file`, replacing what's there.
    private static func write(_ image: CGImage, to file: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(file as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw FrameFailure(errorDescription: "couldn't write \(file.path)")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw FrameFailure(errorDescription: "couldn't write \(file.path)")
        }
    }
}
