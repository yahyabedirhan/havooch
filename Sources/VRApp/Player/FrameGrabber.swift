import AVFoundation
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// What the model asks for a comment's picture: AVFoundation in the app, a
/// fake in tests.
protocol FrameGrabbing: Sendable {
    /// Writes the frame the video shows at `seconds` as a PNG at `file`,
    /// creating its folder, and returns the frame's size in pixels.
    func writeKeyframe(of video: URL, at seconds: Double, to file: URL) async throws -> CGSize
}

/// Why a frame couldn't be saved.
struct FrameFailure: LocalizedError {
    var errorDescription: String?
}

/// Frames read from the video file itself, never from the screen: a comment
/// made in the window and one made from the command line at the same time
/// give the same pixels, at any window size.
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
